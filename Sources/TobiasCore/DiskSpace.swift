import Foundation

public struct DiskSpace: Codable, Sendable, Equatable {
    public var total: Int64
    /// What Finder reports as available (includes purgeable space).
    public var availableImportant: Int64
    /// What `df` reports as available.
    public var availableRaw: Int64

    public var used: Int64 { total - availableRaw }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public init(total: Int64, availableImportant: Int64, availableRaw: Int64) {
        self.total = total
        self.availableImportant = availableImportant
        self.availableRaw = availableRaw
    }

    public static func read(path: String = "/System/Volumes/Data") throws -> DiskSpace {
        let url = URL(fileURLWithPath: path)
        let v = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let total = Int64(v.volumeTotalCapacity ?? 0)
        let raw = Int64(v.volumeAvailableCapacity ?? 0)
        let important = v.volumeAvailableCapacityForImportantUsage ?? raw
        return DiskSpace(total: total, availableImportant: important, availableRaw: raw)
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB, .useTB, .useKB]
        return f.string(fromByteCount: bytes)
    }

    /// Rounded to a whole number of GB (MB below 1 GB), for tight spots like the menu bar: "64 GB".
    public static func whole(_ bytes: Int64) -> String {
        let unit: Int64 = bytes >= 1_000_000_000 ? 1_000_000_000 : 1_000_000
        let rounded = Int64((Double(bytes) / Double(unit)).rounded()) * unit
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: rounded)
    }
}
