import AppKit
import SwiftUI
import Testing
@testable import BoostGaugeKit

@MainActor
struct SettingsViewTests {
    private func makeModel(_ suite: TestDefaults, loginItem: LoginItemControl = .inert) -> (SettingsModel, AppContext) {
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        return (SettingsModel(ctx, loginItem: loginItem), ctx)
    }

    @Test func togglesWriteSettings() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        for id in ItemID.allCases {
            let binding = model.shown(id)
            binding.wrappedValue = true
            #expect(ctx.settings.isShown(id), "\(id)")
            binding.wrappedValue = false
            #expect(!ctx.settings.isShown(id), "\(id)")
        }
        #expect(ctx.settings.allHidden)
        #expect(AppSettings(defaults: suite.reopen()).allHidden)
    }

    @Test func listFollowsStoredOrder() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        #expect(model.order == ItemID.allCases)
        ctx.settings.itemOrder = [.power, .battery, .cpu, .gpu, .memory, .temps, .network, .disk]
        #expect(model.order.first == .power)
    }

    @Test func dragMoveWritesOrder() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        model.move(fromOffsets: IndexSet(integer: 7), toOffset: 0)
        #expect(ctx.settings.itemOrder == [.power, .battery, .cpu, .gpu, .memory, .temps, .network, .disk])
        #expect(AppSettings(defaults: suite.reopen()).itemOrder == ctx.settings.itemOrder)
    }

    @Test func dropSavesOrder() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        model.drop(.battery, onto: .disk)
        #expect(ctx.settings.itemOrder == [.cpu, .gpu, .memory, .temps, .network, .disk, .battery, .power])
        #expect(suite.defaults.stringArray(forKey: "item.order") == ctx.settings.itemOrder.map(\.rawValue))
        model.drop(.power, onto: .cpu)
        #expect(ctx.settings.itemOrder == [.power, .cpu, .gpu, .memory, .temps, .network, .disk, .battery])
        #expect(AppSettings(defaults: suite.reopen()).itemOrder == ctx.settings.itemOrder)
    }

    @Test func dropOnSelfWritesNothing() {
        let suite = TestDefaults()
        let (model, _) = makeModel(suite)
        model.drop(.cpu, onto: .cpu)
        #expect(suite.defaults.object(forKey: "item.order") == nil)
    }

    @Test func moveUpAndDownStopAtTheEnds() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        #expect(!model.canMove(.battery, by: -1))
        #expect(!model.canMove(.power, by: 1))
        model.move(.battery, by: -1)
        #expect(ctx.settings.itemOrder == ItemID.allCases)
        model.move(.cpu, by: -1)
        #expect(ctx.settings.itemOrder.prefix(2) == [.cpu, .battery])
        model.move(.cpu, by: 1)
        #expect(ctx.settings.itemOrder == ItemID.allCases)
    }

    @Test func itemTitlesInMenuBarOrder() {
        #expect(ItemID.allCases.map(SettingsModel.title) ==
                ["Battery", "CPU", "GPU", "Memory", "Temperatures", "Network", "Disk", "Power"])
    }

    @Test func showPercentageAndRefreshWriteSettings() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        model.showPercentage.wrappedValue = false
        #expect(!ctx.settings.showBatteryPercentage)
        model.refreshSeconds.wrappedValue = 5
        #expect(ctx.settings.refreshSeconds == 5)
        #expect(SettingsModel.refreshChoices.map(\.title) == ["1 s", "2 s", "5 s", "10 s"])
        #expect(SettingsModel.refreshChoices.map(\.seconds) == AppSettings.allowedRefreshSeconds)
    }

    @Test func displayPickersWriteSettings() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        model.temperatureUnit.wrappedValue = .fahrenheit
        model.networkUnit.wrappedValue = .bits
        model.captionAlignment.wrappedValue = .leading
        #expect(ctx.settings.temperatureUnit == .fahrenheit)
        #expect(ctx.settings.networkUnit == .bits)
        #expect(ctx.settings.captionAlignment == .leading)
        #expect(TemperatureUnit.allCases.map(SettingsModel.title) == ["°C", "°F"])
        #expect(NetworkUnit.allCases.map(SettingsModel.title) == ["Bytes", "Bits"])
        #expect(CaptionAlignment.allCases.map(SettingsModel.title) == ["Centered", "Left"])
    }

    @Test func launchAtLoginTogglesLoginItem() {
        let suite = TestDefaults()
        var enabled = false
        let (model, _) = makeModel(suite, loginItem: LoginItemControl(isEnabled: { enabled }, setEnabled: { enabled = $0 }))
        #expect(model.launchAtLogin.wrappedValue == false)
        model.launchAtLogin.wrappedValue = true
        #expect(enabled)
        #expect(model.launchAtLogin.wrappedValue)
    }

    @Test func energyModeStatusText() {
        #expect(SettingsModel.statusText(.enabled) == "On")
        #expect(SettingsModel.statusText(.requiresApproval) == "Needs Approval")
        #expect(SettingsModel.statusText(.notRegistered) == "Off")
        #expect(SettingsModel.statusText(.unavailable) == "Off")
    }

    @Test func energyModeSectionOnlyWithService() {
        let suite = TestDefaults()
        let (model, ctx) = makeModel(suite)
        #expect(model.energyModeStatus == nil)
        let fake = FakeEnergyMode()
        ctx.energyMode = fake
        #expect(model.energyModeStatus == "Needs Approval")
        model.openLoginItems()
        #expect(fake.openedLoginItems == 1)
    }

    @Test func installSetsSettingsViewAndHooks() {
        let suite = TestDefaults()
        let ctx = AppContext(settings: AppSettings(defaults: suite.defaults), powerSource: PowerSourceMonitor(initial: .adapter))
        var opened = 0
        SettingsFeature.install(ctx, defaults: suite.defaults, loginItem: .inert, open: { opened += 1 })
        #expect(ctx.onLaunch != nil)
        #expect(ctx.onReopen != nil)
        ctx.onLaunch?()
        #expect(opened == 0)
        ctx.onReopen?()
        #expect(opened == 1)
        for id in ItemID.allCases { ctx.settings.setShown(id, false) }
        ctx.onLaunch?()
        #expect(opened == 2)
        #expect(NSHostingView(rootView: ctx.settingsView).fittingSize.height > 100)
    }
}

@MainActor
private final class FakeEnergyMode: EnergyModeService {
    var helperStatus: HelperStatus = .requiresApproval
    var openedLoginItems = 0
    func openLoginItems() { openedLoginItems += 1 }
    func makeSection() -> AnyView { AnyView(EmptyView()) }
}
