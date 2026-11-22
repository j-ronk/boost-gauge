import Foundation
import IOKit.ps
import Observation

/// Which source powers the Mac, pushed by IOPS notifications rather than polled.
@MainActor @Observable public final class PowerSourceMonitor {
    public private(set) var current: PowerSource

    @ObservationIgnored private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?

    public init() {
        current = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Added to the main run loop below, so the callback always arrives on the main thread.
            MainActor.assumeIsolated {
                let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
                let now = PowerSourceMonitor.read()
                if monitor.current != now { monitor.current = now }
            }
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Test seam: a fixed source with no IOPS subscription.
    init(initial: PowerSource) {
        current = initial
    }

    /// Test seam: what an IOPS notification would do.
    func simulate(_ source: PowerSource) {
        current = source
    }

    deinit {
        // The callback holds an unretained pointer to self, so the source must die with us.
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
    }

    nonisolated static func read() -> PowerSource {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else {
            return .adapter
        }
        return type == kIOPSBatteryPowerValue ? .battery : .adapter
    }
}
