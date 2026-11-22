import Foundation
import IOKit

/// Per-app GPU time. Each process that talks to the GPU holds a user client under the IOAccelerator, and each client's
/// undocumented `AppUsage` lists its command queues with `accumulatedGPUTime` in nanoseconds (checked against wall
/// time and Device Utilization on an M1 Max).
enum GPUClients {
    /// `IOUserClientCreator` reads "pid 176, WindowServer"; the name is cut to 16 characters, so it's never shown.
    static func creator(_ text: String) -> (pid: pid_t, name: String)? {
        guard text.hasPrefix("pid "), let comma = text.firstIndex(of: ",") else { return nil }
        guard let pid = pid_t(text[text.index(text.startIndex, offsetBy: 4)..<comma]), pid > 0 else { return nil }
        return (pid, text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces))
    }

    static func gpuTime(_ clients: [[String: Any]]) -> [pid_t: UInt64] {
        var totals: [pid_t: UInt64] = [:]
        for client in clients {
            guard let text = client["IOUserClientCreator"] as? String, let pid = creator(text)?.pid,
                  let usage = client["AppUsage"] as? [[String: Any]] else { continue }
            let time = usage.reduce(UInt64(0)) { $0 &+ ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
            totals[pid, default: 0] &+= time
        }
        return totals
    }

    /// Only pids present in both readings with a growing total: a new pid's total covers its whole life, and a
    /// shrinking one means a client closed mid-interval.
    static func percents(previous: [pid_t: UInt64], current: [pid_t: UInt64], elapsed: TimeInterval) -> [pid_t: Double] {
        guard elapsed > 0 else { return [:] }
        var result: [pid_t: Double] = [:]
        for (pid, now) in current {
            guard let before = previous[pid], now > before else { continue }
            result[pid] = min(100, Double(now - before) / 1e9 / elapsed * 100)
        }
        return result
    }

    /// Apps by summed GPU %, each with its busiest pid for name and icon. Apps that would read "0%" are left out.
    static func top(_ percents: [pid_t: Double], key: (pid_t) -> String, n: Int) -> [(key: String, pid: pid_t, percent: Double)] {
        var sums: [String: (pid: pid_t, best: Double, total: Double)] = [:]
        for (pid, percent) in percents {
            let k = key(pid)
            var entry = sums[k] ?? (pid, percent, 0)
            if percent > entry.best || (percent == entry.best && pid < entry.pid) { entry.pid = pid; entry.best = percent }
            entry.total += percent
            sums[k] = entry
        }
        return Array(sums
            .filter { $0.value.total.rounded() >= 1 }
            .map { (key: $0.key, pid: $0.value.pid, percent: min(100, $0.value.total)) }
            .sorted { $0.percent != $1.percent ? $0.percent > $1.percent : $0.key < $1.key }
            .prefix(n))
    }

    /// The cheap path rollup Memory uses, so only the winners pay for `AppIdentity.resolve`.
    static func appKey(_ pid: pid_t) -> String {
        let path = ProcessSampler.executablePath(pid)
        return AppIdentity.owningAppPath(pid: pid, executablePath: path)
            ?? "cmd:" + AppIdentity.displayName(processName: ProcessSampler.name(pid), executablePath: path)
    }

    /// Reads just the two properties each user client needs.
    static func read() -> [[String: Any]] {
        var result: [[String: Any]] = []
        GPUReader.forEachAccelerator { service in
            var children: io_iterator_t = IO_OBJECT_NULL
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
                defer { IOObjectRelease(child) }
                guard let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                      let usage = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() else { continue }
                result.append(["IOUserClientCreator": creator, "AppUsage": usage])
            }
        }
        return result
    }
}
