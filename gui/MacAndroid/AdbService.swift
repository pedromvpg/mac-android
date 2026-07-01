import Foundation

struct AndroidDevice: Identifiable, Equatable {
    let id: String
    let model: String?
    let product: String?
}

enum AdbError: LocalizedError {
    case adbNotFound
    case noDevice
    case multipleDevices([String])
    case commandFailed(String)
    case pushFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb not found. Run mac-android setup in Terminal."
        case .noDevice:
            return "No Android device detected. Connect via USB and enable USB debugging."
        case .multipleDevices(let ids):
            return "Multiple devices connected: \(ids.joined(separator: ", ")). Disconnect extras or set ANDROID_SERIAL."
        case .commandFailed(let message):
            return message
        case .pushFailed(let message):
            return message
        }
    }
}

@MainActor
final class AdbService: ObservableObject {
    static let defaultRemote = "/sdcard/Download"

    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var adbVersion: String?
    @Published private(set) var isTransferring = false
    @Published private(set) var transferLog: [TransferEntry] = []

    private var pollTask: Task<Void, Never>?

    struct TransferEntry: Identifiable {
        let id = UUID()
        let name: String
        let remotePath: String
        let timestamp: Date
        let success: Bool
        let detail: String
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let adb = Self.adbPath else {
            devices = []
            adbVersion = nil
            return
        }

        adbVersion = await runOutput(adb, arguments: ["version"])?
            .split(separator: "\n")
            .first
            .map(String.init)

        let output = await runOutput(adb, arguments: ["devices", "-l"]) ?? ""
        devices = Self.parseDevices(output)
    }

    func push(urls: [URL], to remoteBase: String) async {
        guard !urls.isEmpty else { return }
        isTransferring = true
        defer { isTransferring = false }

        do {
            try await validateDevice()
            let adb = try adbExecutable()

            for url in urls {
                let name = url.lastPathComponent
                var remote = remoteBase.hasSuffix("/") ? String(remoteBase.dropLast()) : remoteBase
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    remote = "\(remote)/\(name)"
                }

                let (output, exitCode) = await run(adb, arguments: ["push", url.path, remote])
                logTransfer(name: name, remotePath: remote, success: exitCode == 0, detail: output ?? "")
            }
        } catch {
            logTransfer(
                name: urls.map(\.lastPathComponent).joined(separator: ", "),
                remotePath: remoteBase,
                success: false,
                detail: error.localizedDescription
            )
        }
    }

    func pull(remote: String, to localURL: URL) async {
        isTransferring = true
        defer { isTransferring = false }

        do {
            try await validateDevice()
            let adb = try adbExecutable()
            let (output, exitCode) = await run(adb, arguments: ["pull", remote, localURL.path])
            logTransfer(name: localURL.lastPathComponent, remotePath: remote, success: exitCode == 0, detail: output ?? "")
        } catch {
            logTransfer(name: localURL.lastPathComponent, remotePath: remote, success: false, detail: error.localizedDescription)
        }
    }

    func listDirectory(at path: String) async throws -> [RemoteFile] {
        try await validateDevice()
        let adb = try adbExecutable()
        let resolved = await resolveRemotePath(path, adb: adb)
        let output = await runOutput(adb, arguments: ["shell", "ls", "-la", "--", Self.shellEscape(resolved)]) ?? ""

        let lowered = output.lowercased()
        if lowered.contains("permission denied") || lowered.contains("no such file") {
            throw AdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let files = RemoteFileParser.parseListing(output, in: resolved)
        if files.isEmpty, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !output.contains("total ") {
            throw AdbError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return files
    }

    func fetchStorage() async throws -> [StorageVolume] {
        try await validateDevice()
        let adb = try adbExecutable()

        let summaryOutput = await runOutput(adb, arguments: [
            "shell", "df", "-h",
            "/storage/emulated/0", "/storage/emulated", "/data", "/cache", "/",
        ]) ?? ""

        let fullOutput = await runOutput(adb, arguments: ["shell", "df", "-h"]) ?? ""
        let combined = summaryOutput + "\n" + fullOutput

        var seen: Set<String> = []
        var volumes: [StorageVolume] = []
        for volume in StorageParser.parse(combined) {
            if seen.insert(volume.mountPoint).inserted {
                volumes.append(volume)
            }
        }

        if volumes.isEmpty {
            throw AdbError.commandFailed("Could not parse storage information from device.")
        }

        return volumes.sorted { $0.mountPoint.localizedCaseInsensitiveCompare($1.mountPoint) == .orderedAscending }
    }

    private func resolveRemotePath(_ path: String, adb: String) async -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        let output = await runOutput(adb, arguments: ["shell", "readlink", "-f", Self.shellEscape(trimmed)]) ?? trimmed
        let resolved = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? trimmed : resolved
    }

    /// Wraps a remote path in single quotes and escapes any embedded single quotes,
    /// making it safe to pass as an argument in an `adb shell` command where the
    /// Android shell would otherwise interpret metacharacters (`;`, `$()`, `|`, etc.).
    private static func shellEscape(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func logTransfer(name: String, remotePath: String, success: Bool, detail: String) {
        transferLog.insert(
            TransferEntry(
                name: name,
                remotePath: remotePath,
                timestamp: .now,
                success: success,
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            at: 0
        )
    }

    private func validateDevice() async throws {
        await refresh()
        if devices.isEmpty { throw AdbError.noDevice }
        if devices.count > 1, ProcessInfo.processInfo.environment["ANDROID_SERIAL"] == nil {
            throw AdbError.multipleDevices(devices.map(\.id))
        }
    }

    private func adbExecutable() throws -> String {
        guard let path = Self.adbPath else { throw AdbError.adbNotFound }
        return path
    }

    static var adbPath: String? {
        var candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            candidates += pathEnv.split(separator: ":").map { "\($0)/adb" }
        }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }

        let (output, _) = Self.runSync("/usr/bin/which", arguments: ["adb"])
        if let output, !output.isEmpty { return output.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private static func parseDevices(_ output: String) -> [AndroidDevice] {
        output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2, parts[1] == "device" else { return nil }
                let id = String(parts[0])
                let rest = String(line)
                let model = rest.firstMatch(for: #"model:(\S+)"#)
                let product = rest.firstMatch(for: #"product:(\S+)"#)
                return AndroidDevice(id: id, model: model, product: product)
            }
    }

    private func run(_ launchPath: String, arguments: [String]) async -> (output: String?, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runSync(launchPath, arguments: arguments))
            }
        }
    }

    private func runOutput(_ launchPath: String, arguments: [String]) async -> String? {
        await run(launchPath, arguments: arguments).output
    }

    private static nonisolated func runSync(_ launchPath: String, arguments: [String]) -> (output: String?, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8), process.terminationStatus)
        } catch {
            return (nil, -1)
        }
    }
}

private extension String {
    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[capture])
    }
}
