import Foundation

struct RemoteFile: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64?
    let permissions: String
    let modified: String?

    var id: String { path }

    var iconName: String {
        if isSymlink { return "link" }
        if isDirectory { return "folder.fill" }
        return "doc.fill"
    }
}

enum RemoteFileParser {
    static func parseListing(_ output: String, in directory: String) -> [RemoteFile] {
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory

        return output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                parseLine(String(line), base: base)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func parseLine(_ line: String, base: String) -> RemoteFile? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("total ") { return nil }
        if trimmed == "." || trimmed == ".." { return nil }

        // drwxrws---  2 u0_a170 media_rw  3452 2026-06-20 16:02 Download
        let pattern = #"^([dl-])([rwxsStT-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 6,
              let permRange = Range(match.range(at: 2), in: trimmed),
              let sizeRange = Range(match.range(at: 3), in: trimmed),
              let dateRange = Range(match.range(at: 4), in: trimmed),
              let nameRange = Range(match.range(at: 5), in: trimmed) else {
            return nil
        }

        let typeChar = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 0)]
        let permissions = String(trimmed[permRange])
        let size = Int64(trimmed[sizeRange])
        let modified = String(trimmed[dateRange])
        var name = String(trimmed[nameRange])

        let isSymlink = typeChar == "l"
        var isDirectory = typeChar == "d"

        if isSymlink, let arrow = name.range(of: " -> ") {
            let target = String(name[arrow.upperBound...])
            name = String(name[..<arrow.lowerBound])
            isDirectory = target.hasPrefix("/") || target.hasSuffix("/")
        }

        if name.hasSuffix("/") {
            name = String(name.dropLast())
            isDirectory = true
        }

        let path = base.isEmpty ? "/\(name)" : "\(base)/\(name)"

        return RemoteFile(
            name: name,
            path: path,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            permissions: permissions,
            modified: modified
        )
    }
}

struct RemoteBookmark: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let systemImage: String

    static let defaults: [RemoteBookmark] = [
        RemoteBookmark(id: "sdcard", name: "Internal storage", path: "/storage/emulated/0", systemImage: "internaldrive"),
        RemoteBookmark(id: "storage", name: "Storage", path: "/storage", systemImage: "externaldrive"),
        RemoteBookmark(id: "root", name: "Root", path: "/", systemImage: "folder"),
        RemoteBookmark(id: "system", name: "System", path: "/system", systemImage: "gearshape"),
        RemoteBookmark(id: "data", name: "Data", path: "/data", systemImage: "lock.fill"),
    ]
}
