import Foundation

struct ProcessCPUTime {
    var pid: pid_t
    var name: String
    var cpuNanos: UInt64
}

/// In-process replacement for polling `ps`/`top`. It only sees processes owned by this user:
/// root and other-user daemons (WindowServer, kernel_task) refuse `proc_pid_rusage` without privileges.
enum ProcessSampler {
    static func snapshot() -> [ProcessCPUTime] {
        let timebase = machTimebase
        return allPids().compactMap { pid in
            guard let usage = rusage(pid) else { return nil }
            // rusage CPU times are mach ticks on Apple Silicon, not nanoseconds.
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanos = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer)).partialValue / UInt64(max(1, timebase.denom))
            // Names are looked up in `top`, for the winners only.
            return ProcessCPUTime(pid: pid, name: "", cpuNanos: nanos)
        }
    }

    /// Percent of one core, as `top` and Activity Monitor show it, so a multi-threaded process can exceed 100%.
    static func top(previous: [ProcessCPUTime], current: [ProcessCPUTime], elapsed: TimeInterval, n: Int)
        -> [(pid: pid_t, name: String, percent: Double)] {
        guard elapsed > 0 else { return [] }
        let before = Dictionary(previous.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: { a, _ in a })
        let rows: [(pid: pid_t, name: String, percent: Double)] = current.compactMap { p in
            // A pid not in the last snapshot has no baseline; one whose time went down was reused by a new process.
            guard let old = before[p.pid], p.cpuNanos >= old else { return nil }
            return (p.pid, p.name, Double(p.cpuNanos - old) / (elapsed * 1e9) * 100)
        }
        return rows.filter { $0.percent > 0 }.sorted { $0.percent > $1.percent }.prefix(n)
            .map { ($0.pid, $0.name.isEmpty ? name($0.pid) : $0.name, $0.percent) }
    }

    static func footprints() -> [(pid: pid_t, bytes: UInt64)] {
        allPids().compactMap { pid in rusage(pid).map { (pid, $0.ri_phys_footprint) } }
    }

    static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return executablePath(pid, buffer: &buffer)
    }

    /// Reuses the caller's buffer, for loops over every pid.
    static func executablePath(_ pid: pid_t, buffer: inout [CChar]) -> String {
        proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }

    static func name(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : "pid \(pid)"
    }

    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func allPids() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? info : nil
    }
}
