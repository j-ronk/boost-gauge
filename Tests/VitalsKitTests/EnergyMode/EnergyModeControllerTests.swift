import Foundation
import ServiceManagement
import Testing
@testable import VitalsKit

/// Shared call log so tests can assert ordering across the fakes.
@MainActor final class CallLog {
    var calls: [String] = []
}

@MainActor final class FakeHelperClient: HelperClient {
    let log: CallLog
    var result = true
    var sent: [PowerModeCommand] = []
    /// Runs as the helper would, before replying: lets a test change what the next read sees.
    var onSend: ((PowerModeCommand) -> Void)?
    /// Awaited mid-call, while the helper is still "working".
    var during: (() async -> Void)?

    init(_ log: CallLog) { self.log = log }

    func setPowerMode(_ command: PowerModeCommand) async -> Bool {
        log.calls.append("set \(command.arguments.joined(separator: " "))")
        sent.append(command)
        onSend?(command)
        await during?()
        return result
    }
}

@MainActor final class FakeDaemon: DaemonService {
    struct Failure: Error {}
    let log: CallLog
    var status: HelperStatus
    var registerFails = false
    var statusAfterRegister: HelperStatus = .requiresApproval

    init(_ log: CallLog, status: HelperStatus) {
        self.log = log
        self.status = status
    }

    func register() throws {
        log.calls.append("register")
        if registerFails { throw Failure() }
        status = statusAfterRegister
    }

    func openLoginItems() {
        log.calls.append("openLoginItems")
    }
}

@MainActor final class FakeReader: ModeReader {
    let log: CallLog
    var modes: [PowerSource: EnergyMode]

    init(_ log: CallLog, modes: [PowerSource: EnergyMode]) {
        self.log = log
        self.modes = modes
    }

    var reads: Int { log.calls.filter { $0 == "read" }.count }

    /// Awaited after the snapshot is taken, to model a slow `pmset -g custom`.
    var during: (() async -> Void)?

    func read() async -> [PowerSource: EnergyMode] {
        log.calls.append("read")
        let snapshot = modes
        if let during {
            self.during = nil
            await during()
        }
        return snapshot
    }
}

@MainActor struct Harness {
    let log = CallLog()
    let monitor: PowerSourceMonitor
    let client: FakeHelperClient
    let daemon: FakeDaemon
    let reader: FakeReader
    let controller: EnergyModeController

    /// A real-world split: Battery = Automatic, Adapter = High.
    init(source: PowerSource = .adapter, status: HelperStatus = .enabled,
         modes: [PowerSource: EnergyMode] = [.battery: .automatic, .adapter: .high]) {
        monitor = PowerSourceMonitor(initial: source)
        client = FakeHelperClient(log)
        daemon = FakeDaemon(log, status: status)
        reader = FakeReader(log, modes: modes)
        controller = EnergyModeController(source: monitor, client: client, daemon: daemon, reader: reader)
        // A successful pmset changes only the targeted source, which is what the next read reports.
        client.onSend = { [reader] command in
            guard let source = PowerSource(rawValue: command.rawSource),
                  let mode = EnergyMode(rawValue: command.rawMode) else { return }
            reader.modes[source] = mode
        }
    }

    /// Source changes refresh on a hop through the main actor; give that a bounded chance to land.
    func settle(until done: () -> Bool) async {
        var i = 0
        while !done() && i < 200 {
            try? await Task.sleep(for: .milliseconds(5))
            i += 1
        }
    }
}

@MainActor
struct EnergyModeControllerTests {
    @Test func displaysNothingBeforeFirstRead() {
        let h = Harness()
        #expect(h.controller.displayedMode == nil)
        #expect(h.reader.reads == 0)
    }

    @Test func refreshShowsCurrentSourceMode() async {
        let h = Harness(source: .adapter)
        await h.controller.refresh()
        #expect(h.controller.displayedMode == .high)
        #expect(h.controller.source == .adapter)
    }

    @Test func notApprovedOpensLoginItemsAndKeepsMode() async {
        let h = Harness(status: .requiresApproval)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.log.calls.filter { $0 == "openLoginItems" }.count == 1)
        #expect(h.client.sent.isEmpty)
        #expect(!h.log.calls.contains("register"))
        #expect(h.controller.displayedMode == .high)
        #expect(h.controller.pickerSelection == .high)
    }

    @Test func notRegisteredRegistersThenOpensLoginItems() async {
        let h = Harness(status: .notRegistered)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.log.calls.filter { $0 != "read" } == ["register", "openLoginItems"])
        #expect(h.client.sent.isEmpty)
        #expect(h.controller.displayedMode == .high)
    }

    @Test func registerFailureStillOpensLoginItems() async {
        let h = Harness(status: .notRegistered)
        h.daemon.registerFails = true
        await h.controller.refresh()
        await h.controller.select(.automatic)
        #expect(h.log.calls.filter { $0 != "read" } == ["register", "openLoginItems"])
        #expect(h.client.sent.isEmpty)
        #expect(h.controller.displayedMode == .high)
    }

    // macOS 27 reports a never-registered daemon as .notFound, which maps to .unavailable.
    @Test func unavailableRegistersThenOpensLoginItems() async {
        let h = Harness(status: .unavailable)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.log.calls.filter { $0 != "read" } == ["register", "openLoginItems"])
        #expect(h.client.sent.isEmpty)
    }

    @Test func enabledSetsCurrentSourceOnly() async {
        let h = Harness(source: .adapter)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.client.sent.map(\.arguments) == [["-c", "powermode", "1"]])
        #expect(h.controller.displayedMode == .low)
        #expect(h.reader.modes[.battery] == .automatic)
        #expect(!h.log.calls.contains("openLoginItems"))
    }

    @Test func enabledOnBatteryUsesDashB() async {
        let h = Harness(source: .battery)
        await h.controller.refresh()
        await h.controller.select(.high)
        #expect(h.client.sent.map(\.arguments) == [["-b", "powermode", "2"]])
        #expect(h.controller.displayedMode == .high)
        #expect(h.reader.modes[.adapter] == .high)
    }

    @Test func setIsFollowedByReread() async {
        let h = Harness()
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.log.calls == ["read", "set -c powermode 1", "read"])
    }

    @Test func failedSetShowsRealMode() async {
        let h = Harness(source: .adapter)
        h.client.result = false
        h.client.onSend = nil
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.client.sent.count == 1)
        #expect(h.reader.reads == 2)
        #expect(h.controller.displayedMode == .high)
        #expect(h.controller.pickerSelection == .high)
    }

    @Test func pickerShowsChoiceWhileSetting() async {
        let h = Harness()
        await h.controller.refresh()
        var during: (picker: EnergyMode?, truth: EnergyMode?)?
        let controller = h.controller
        h.client.onSend = { _ in during = (controller.pickerSelection, controller.displayedMode) }
        await h.controller.select(.low)
        #expect(during?.picker == .low)
        #expect(during?.truth == .high)
        #expect(h.controller.pickerSelection == h.controller.displayedMode)
    }

    @Test func secondPickWhileSettingIsDropped() async {
        let h = Harness()
        await h.controller.refresh()
        let controller = h.controller
        h.client.during = { await controller.select(.automatic) }
        await h.controller.select(.low)
        #expect(h.client.sent.map(\.arguments) == [["-c", "powermode", "1"]])
        #expect(h.controller.refusals == 1)
        #expect(h.controller.displayedMode == .low)
    }

    @Test func refusedPickRebuildsControl() async {
        let h = Harness(status: .requiresApproval)
        await h.controller.refresh()
        #expect(h.controller.refusals == 0)
        await h.controller.select(.low)
        #expect(h.controller.refusals == 1)
    }

    @Test func staleReadIsDiscarded() async {
        let h = Harness()
        let controller = h.controller
        let reader = h.reader
        // The first read snapshots High, then a newer read lands Low before the first returns.
        h.reader.during = {
            reader.modes[.adapter] = .low
            await controller.refresh()
        }
        await h.controller.refresh()
        #expect(h.reader.reads == 2)
        #expect(h.controller.displayedMode == .low)
    }

    @Test func failedReadKeepsLastKnownModes() async {
        let h = Harness()
        await h.controller.refresh()
        h.reader.modes = [:]
        await h.controller.refresh()
        #expect(h.controller.displayedMode == .high)
    }

    @Test func selectBeforeAnyReadDoesNothing() async {
        let h = Harness(status: .requiresApproval)
        await h.controller.select(.low)
        h.daemon.status = .enabled
        await h.controller.select(.low)
        #expect(h.log.calls.isEmpty)
    }

    @Test func pendingPickStaysWithItsSource() async {
        let h = Harness(source: .adapter)
        await h.controller.refresh()
        let controller = h.controller
        let monitor = h.monitor
        var shownOnBattery: EnergyMode?
        h.client.during = {
            monitor.simulate(.battery)
            shownOnBattery = controller.pickerSelection
        }
        await h.controller.select(.low)
        #expect(shownOnBattery == .automatic)
    }

    @Test func selectingCurrentModeDoesNothing() async {
        let h = Harness()
        await h.controller.refresh()
        await h.controller.select(.high)
        #expect(h.client.sent.isEmpty)
        #expect(h.log.calls == ["read"])
    }

    @Test func sourceChangeRereadsMode() async {
        let h = Harness(source: .adapter)
        await h.controller.refresh()
        #expect(h.controller.displayedMode == .high)
        // Changed elsewhere (System Settings) since our last read.
        h.reader.modes[.battery] = .low
        h.monitor.simulate(.battery)
        #expect(h.controller.source == .battery)
        await h.settle { h.reader.reads >= 2 }
        #expect(h.reader.reads == 2)
        #expect(h.controller.displayedMode == .low)

        h.reader.modes[.adapter] = .automatic
        h.monitor.simulate(.adapter)
        await h.settle { h.reader.reads >= 3 }
        #expect(h.controller.displayedMode == .automatic)
    }

    @Test func sourceChangeAfterSetTargetsNewSource() async {
        let h = Harness(source: .adapter)
        await h.controller.refresh()
        h.monitor.simulate(.battery)
        await h.settle { h.reader.reads >= 2 }
        await h.controller.select(.low)
        #expect(h.client.sent.map(\.arguments) == [["-b", "powermode", "1"]])
        #expect(h.reader.modes[.adapter] == .high)
    }

    @Test func revokedAfterEnableBehavesAsNotApproved() async {
        let h = Harness(status: .enabled)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.controller.displayedMode == .low)

        h.daemon.status = .requiresApproval
        await h.controller.select(.automatic)
        #expect(h.client.sent.count == 1)
        #expect(h.log.calls.filter { $0 == "openLoginItems" }.count == 1)
        #expect(h.controller.displayedMode == .low)
        #expect(h.controller.pickerSelection == .low)
    }

    @Test func approvalLaterLetsSelectThrough() async {
        let h = Harness(status: .requiresApproval)
        await h.controller.refresh()
        await h.controller.select(.low)
        #expect(h.client.sent.isEmpty)
        h.daemon.status = .enabled
        await h.controller.select(.low)
        #expect(h.client.sent.map(\.arguments) == [["-c", "powermode", "1"]])
        #expect(h.controller.displayedMode == .low)
    }

    @Test func helperStatusIsLive() {
        let h = Harness(status: .notRegistered)
        #expect(h.controller.helperStatus == .notRegistered)
        h.daemon.status = .enabled
        #expect(h.controller.helperStatus == .enabled)
    }

    @Test func openLoginItemsForwards() {
        let h = Harness()
        h.controller.openLoginItems()
        #expect(h.log.calls == ["openLoginItems"])
    }

    @Test func unreadableModesShowNothing() async {
        let h = Harness(modes: [:])
        await h.controller.refresh()
        #expect(h.controller.displayedMode == nil)
        #expect(h.controller.pickerSelection == nil)
    }

    @Test func headingFollowsSource() {
        let h = Harness(source: .battery)
        #expect(h.controller.sourceTitle == "Battery")
        h.monitor.simulate(.adapter)
        #expect(h.controller.sourceTitle == "Power Adapter")
    }

    @Test(arguments: [
        (SMAppService.Status.enabled, HelperStatus.enabled),
        (.requiresApproval, .requiresApproval),
        (.notRegistered, .notRegistered),
        (.notFound, .unavailable),
    ])
    func daemonStatusMapping(raw: SMAppService.Status, expected: HelperStatus) {
        #expect(HelperStatus(raw) == expected)
    }
}
