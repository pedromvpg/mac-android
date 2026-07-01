import Foundation

struct StorageVolume: Identifiable, Hashable {
    let id: String
    let filesystem: String
    let size: String
    let used: String
    let available: String
    let usePercent: Int
    let mountPoint: String

    var label: String {
        switch mountPoint {
        case "/storage/emulated/0", "/storage/emulated":
            return "Internal storage"
        case "/data":
            return "Data partition"
        case let path where path.hasPrefix("/data/"):
            return "Data partition"
        case "/cache":
            return "Cache"
        case "/":
            return "System root"
        case "/system":
            return "System"
        case "/vendor":
            return "Vendor"
        default:
            return mountPoint
        }
    }

    var isUserStorage: Bool {
        mountPoint == "/storage/emulated/0"
            || mountPoint == "/storage/emulated"
            || mountPoint.hasPrefix("/storage/")
    }
}

enum StorageParser {
    static func parse(_ output: String) -> [StorageVolume] {
        output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> StorageVolume? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // /dev/fuse  109G  10G  100G   9% /storage/emulated
        let pattern = #"^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)%\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 7,
              let fsRange = Range(match.range(at: 1), in: trimmed),
              let sizeRange = Range(match.range(at: 2), in: trimmed),
              let usedRange = Range(match.range(at: 3), in: trimmed),
              let availRange = Range(match.range(at: 4), in: trimmed),
              let pctRange = Range(match.range(at: 5), in: trimmed),
              let mountRange = Range(match.range(at: 6), in: trimmed) else {
            return nil
        }

        let mount = String(trimmed[mountRange])
        return StorageVolume(
            id: mount,
            filesystem: String(trimmed[fsRange]),
            size: String(trimmed[sizeRange]),
            used: String(trimmed[usedRange]),
            available: String(trimmed[availRange]),
            usePercent: Int(trimmed[pctRange]) ?? 0,
            mountPoint: mount
        )
    }

    static func primaryVolumes(from all: [StorageVolume]) -> [StorageVolume] {
        let preferredMounts = [
            "/storage/emulated/0",
            "/storage/emulated",
            "/data",
        ]

        var result: [StorageVolume] = []
        var seenLabels: Set<String> = []

        for mount in preferredMounts {
            if let volume = all.first(where: { $0.mountPoint == mount }),
               !seenLabels.contains(volume.label) {
                result.append(volume)
                seenLabels.insert(volume.label)
            }
        }

        if result.isEmpty {
            result = all.filter(\.isUserStorage).prefix(1).map { $0 }
        }

        return result
    }
}
