import Foundation
import IOKit

// Apple Silicon's own temperature services, through the private IOHIDEventSystemClient API that Stats and
// powermetrics-style tools use. Read only: nothing here sets anything.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64)
    -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

/// Only the services `TempCatalog.hidSensors` has a name for are kept, found once on first read.
final class HIDTemperatures {
    private static let temperatureEvent: Int64 = 15
    private var services: [(product: String, service: AnyObject)]?
    private var client: AnyObject?

    func read() -> [(product: String, celsius: Double)] {
        let services = self.services ?? discover()
        self.services = services
        return services.compactMap { entry in
            guard let event = IOHIDServiceClientCopyEvent(entry.service, Self.temperatureEvent, 0, 0)?
                .takeRetainedValue() else { return nil }
            return (entry.product, IOHIDEventGetFloatValue(event, Int32(Self.temperatureEvent << 16)))
        }
    }

    private func discover() -> [(product: String, service: AnyObject)] {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return [] }
        self.client = client
        // Vendor usage page 0xff00, usage 5: temperature sensors.
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let all = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        return all.compactMap { service in
            guard let product = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String, Self.isNamed(product) else { return nil }
            return (product, service)
        }
    }

    static func isNamed(_ product: String) -> Bool {
        product == "gas gauge battery" || product.hasPrefix("PMU tdie") || product.hasPrefix("NAND CH")
    }
}
