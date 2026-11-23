import Darwin
import Foundation

struct MemoryStats: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var usedPercent: Double

    /// Activity Monitor's "Memory Used": app memory (internal minus purgeable) + wired + compressed.
    static func from(internal: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64, total: UInt64) -> MemoryStats {
        let appPages = `internal` > purgeable ? `internal` - purgeable : 0
        let used = (appPages + wired + compressed) * pageSize
        return MemoryStats(usedBytes: used, totalBytes: total, usedPercent: total > 0 ? min(100, Double(used) / Double(total) * 100) : 0)
    }

    static func read() -> MemoryStats? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return from(internal: UInt64(info.internal_page_count), purgeable: UInt64(info.purgeable_count),
                    wired: UInt64(info.wire_count), compressed: UInt64(info.compressor_page_count),
                    pageSize: UInt64(vm_kernel_page_size), total: ProcessInfo.processInfo.physicalMemory)
    }

    static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? usage.xsu_used : nil
    }
}

enum MemoryPressure: String {
    case normal = "Normal", warning = "Warning", critical = "Critical"

    init(sysctlLevel: Int) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    /// How hard the system is pressed for memory, 0 to 100: the kernel's free level turned around, the figure
    /// pressure graphs plot.
    static func percent() -> Double? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0, (0...100).contains(level) else { return nil }
        return Double(100 - level)
    }

    static func read() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 ? .init(sysctlLevel: Int(level)) : .normal
    }
}

enum MemoryFormat {
    private static let gib = Double(1 << 30)

    /// "41.2 GB of 64 GB". GiB labelled GB, as Activity Monitor and About This Mac do.
    static func usedOfTotal(used: UInt64, total: UInt64) -> String {
        String(format: "%.1f GB of %.0f GB", Double(used) / gib, (Double(total) / gib).rounded())
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        bytes == 0 ? "0 GB" : String(format: "%.1f GB", Double(bytes) / gib)
    }

    /// Per-app sizes: most apps sit under a gigabyte, where "0.3 GB" says too little.
    static func appSize(_ bytes: UInt64) -> String {
        Double(bytes) < gib ? String(format: "%.0f MB", Double(bytes) / Double(1 << 20)) : gigabytes(bytes)
    }
}

enum MemoryTop {
    static func rollUp(_ rows: [(key: String, bytes: UInt64)], n: Int) -> [(key: String, bytes: UInt64)] {
        var sums: [String: UInt64] = [:]
        for row in rows { sums[row.key, default: 0] &+= row.bytes }
        return Array(sums.map { (key: $0.key, bytes: $0.value) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.key < $1.key }
            .prefix(n))
    }

    /// Top apps by footprint, each with the pid of its largest process for name and icon lookup.
    /// Grouping uses the cheap path rollup so only the winners pay for `AppIdentity.resolve`.
    static func sample(n: Int) -> [(key: String, pid: pid_t, bytes: UInt64)] {
        var rows: [(key: String, bytes: UInt64)] = []
        var biggest: [String: (pid: pid_t, bytes: UInt64)] = [:]
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for (pid, bytes) in ProcessSampler.footprints() {
            let path = ProcessSampler.executablePath(pid, buffer: &buffer)
            let key = AppIdentity.owningAppPath(pid: pid, executablePath: path)
                ?? "cmd:" + AppIdentity.displayName(processName: ProcessSampler.name(pid), executablePath: path)
            rows.append((key, bytes))
            if bytes >= biggest[key]?.bytes ?? 0 { biggest[key] = (pid, bytes) }
        }
        return rollUp(rows, n: n).compactMap { row in biggest[row.key].map { (row.key, $0.pid, row.bytes) } }
    }
}
