import Foundation
import Observation
import SwiftUI

/// The picker's model. It never trusts its own writes: after every attempt it re-reads what macOS reports.
@MainActor @Observable public final class EnergyModeController: EnergyModeService {
    @ObservationIgnored private let monitor: PowerSourceMonitor
    @ObservationIgnored private let client: HelperClient
    @ObservationIgnored private let daemon: DaemonService
    @ObservationIgnored private let reader: ModeReader

    private var modes: [PowerSource: EnergyMode] = [:]
    /// The segment the user just picked, shown only while the helper works on it and only for that source.
    private var pending: (source: PowerSource, mode: EnergyMode)?
    /// Reads can overlap (panel open, source change, after a set); only the newest may land.
    @ObservationIgnored private var readGeneration = 0
    /// Bumped when a pick is refused, so the view can rebuild the control back onto the real mode.
    private(set) var refusals = 0

    init(source: PowerSourceMonitor, client: HelperClient, daemon: DaemonService, reader: ModeReader) {
        monitor = source
        self.client = client
        self.daemon = daemon
        self.reader = reader
        observeSource()
    }

    public convenience init(_ ctx: AppContext) {
        self.init(source: ctx.powerSource, client: XPCHelperClient(), daemon: SMDaemonService(), reader: PmsetModeReader())
    }

    var source: PowerSource { monitor.current }

    var sourceTitle: String { source == .battery ? "Battery" : "Power Adapter" }

    public var displayedMode: EnergyMode? { modes[source] }

    var pickerSelection: EnergyMode? {
        if let pending, pending.source == source { return pending.mode }
        return displayedMode
    }

    public var helperStatus: HelperStatus { daemon.status }

    public func openLoginItems() {
        daemon.openLoginItems()
    }

    public func makeSection() -> AnyView {
        AnyView(EnergyModeSection(controller: self))
    }

    public func select(_ mode: EnergyMode) async {
        // A second pick while one is in flight is dropped, and the control rebuilt so it doesn't show it.
        if pending != nil {
            refusals += 1
            return
        }
        // Nothing read yet means nothing to compare against; the view disables the picker then too.
        guard let current = displayedMode, mode != current else { return }
        let source = self.source
        let status = daemon.status
        guard status == .enabled else {
            // macOS 27 reports a daemon that was never registered as .notFound (.unavailable), not .notRegistered.
            if status == .notRegistered || status == .unavailable {
                do { try daemon.register() } catch {
                    energyModeLog.error("register failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            daemon.openLoginItems()
            refusals += 1
            return
        }
        pending = (source, mode)
        let ok = await client.setPowerMode(PowerModeCommand(source: source, mode: mode))
        if !ok { energyModeLog.error("helper refused \(PowerModeCommand(source: source, mode: mode).arguments, privacy: .public)") }
        await refresh()
        pending = nil
    }

    public func refresh() async {
        readGeneration += 1
        let generation = readGeneration
        let read = await reader.read()
        // An empty read means pmset failed; the last known modes are closer to the truth than nothing.
        guard generation == readGeneration, !read.isEmpty else { return }
        modes = read
    }

    /// A plug or unplug can land with the panel closed, so re-read then rather than on the menu bar tick.
    private func observeSource() {
        withObservationTracking {
            _ = monitor.current
        } onChange: { [weak self] in
            // onChange fires before the new value is stored; hop so refresh sees it.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeSource()
                await self.refresh()
            }
        }
    }
}
