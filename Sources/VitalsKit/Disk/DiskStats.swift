import Foundation

public struct DiskCapacity: Equatable, Sendable {
    public var name: String
    public var available: Int64
    public var total: Int64

    public init(name: String, available: Int64, total: Int64) {
        self.name = name
        self.available = available
        self.total = total
    }

    /// Finder's numbers: "available" includes purgeable space macOS will free on demand, which raw `statfs` misses.
    /// The query asks the CacheDelete service, so it costs tens of milliseconds; callers keep it off the main actor.
    public static func startupVolume() -> DiskCapacity? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeNameKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return DiskCapacity(name: values.volumeName ?? "Disk", available: available, total: Int64(total))
    }
}

public enum DiskStats {
    /// Bytes per second. Counters are summed over every disk, so one going away between samples makes the sum drop;
    /// that reads as 0 rather than a negative rate.
    public static func rates(previous: (read: UInt64, write: UInt64), current: (read: UInt64, write: UInt64),
                             elapsed: TimeInterval) -> (read: Double, write: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let read = current.read >= previous.read ? current.read - previous.read : 0
        let write = current.write >= previous.write ? current.write - previous.write : 0
        return (Double(read) / elapsed, Double(write) / elapsed)
    }

    /// Menu bar form in Finder's decimal units: "412G", "5.4G", "1.2T", "12T".
    public static func freeLabel(_ bytes: Int64) -> String {
        let gb = Double(max(0, bytes)) / 1e9
        if gb < 9.95 { return String(format: "%.1fG", gb) }
        if gb < 999.5 { return "\(Int(gb.rounded()))G" }
        let tb = gb / 1e3
        return tb < 9.95 ? String(format: "%.1fT", tb) : "\(Int(tb.rounded()))T"
    }

    /// Sums "Bytes (Read)" / "Bytes (Write)" from each IOBlockStorageDriver's Statistics.
    public static func totals(_ drivers: [[String: Any]]) -> (read: UInt64, write: UInt64) {
        var read: UInt64 = 0, write: UInt64 = 0
        for driver in drivers {
            guard let stats = driver["Statistics"] as? [String: Any] else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }

    static func readTotals() -> (read: UInt64, write: UInt64) {
        totals(IORegistry.allProperties(ofClass: "IOBlockStorageDriver"))
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
