import Foundation
import Observation

/// Whether macOS is in Low Power Mode for the current power source, pushed by the power state notification.
/// The battery item also re-reads it on its tick: one property read, in case a notification is missed.
@MainActor @Observable final class LowPowerMonitor {
    private(set) var isOn: Bool

    @ObservationIgnored private let read: () -> Bool
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private nonisolated(unsafe) var token: NSObjectProtocol?

    init(read: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
         center: NotificationCenter = .default) {
        self.read = read
        self.center = center
        isOn = read()
        // Posted on whatever thread changed the state.
        token = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
    }

    deinit {
        if let token { center.removeObserver(token) }
    }

    func refresh() {
        let now = read()
        if now != isOn { isOn = now }
    }
}
