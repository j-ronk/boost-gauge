import Foundation
import IOKit

/// There is no public GPU load API; IOAccelerator's `PerformanceStatistics` is undocumented but stable and widely used.
enum GPUReader {
    static func utilization(_ accelerators: [[String: Any]]) -> Double? {
        let values = accelerators.compactMap { service -> Double? in
            guard let stats = service["PerformanceStatistics"] as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue,
                  value.isFinite else { return nil }
            return min(100, max(0, value))
        }
        return values.max()
    }

    static func memoryInUse(_ accelerators: [[String: Any]]) -> UInt64? {
        let values = accelerators.compactMap { service -> UInt64? in
            guard let stats = service["PerformanceStatistics"] as? [String: Any] else { return nil }
            return (stats["In use system memory"] as? NSNumber)?.uint64Value
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    static func coreCount(_ accelerators: [[String: Any]]) -> Int? {
        let total = accelerators.compactMap { ($0["gpu-core-count"] as? NSNumber)?.intValue }.filter { $0 > 0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    static let detailKeys = ["PerformanceStatistics", "gpu-core-count"]

    /// Reads only the named properties, not every property of each accelerator (as `IORegistry.allProperties`
    /// would), because the load read runs on every menu bar tick.
    static func readAccelerators(keys: [String] = ["PerformanceStatistics"]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        forEachAccelerator { service in
            var properties: [String: Any] = [:]
            for key in keys {
                properties[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if !properties.isEmpty { result.append(properties) }
        }
        return result
    }

    static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            body(service)
            IOObjectRelease(service)
        }
    }
}
