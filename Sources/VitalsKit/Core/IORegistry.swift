import Foundation
import IOKit

public enum IORegistry {
    /// Properties of the first service matching `ofClass`.
    public static func properties(ofClass className: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return properties(of: service)
    }

    public static func allProperties(ofClass className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            if let props = properties(of: service) { result.append(props) }
            IOObjectRelease(service)
        }
        return result
    }

    private static func properties(of service: io_service_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }
}
