import Testing
@testable import BoostGaugeKit

@MainActor
struct LaunchAtLoginTests {
    @Test func registersOnlyOnFirstRun() {
        #expect(LaunchAtLogin.shouldRegisterOnFirstRun(alreadyConfigured: false))
        #expect(!LaunchAtLogin.shouldRegisterOnFirstRun(alreadyConfigured: true))
    }

    @Test func firstRunRegistersOnceAndRemembers() {
        let suite = TestDefaults()
        var registered = 0
        let control = LoginItemControl(isEnabled: { registered > 0 }, setEnabled: { if $0 { registered += 1 } })
        LaunchAtLogin.configureOnFirstRun(defaults: suite.defaults, control: control)
        LaunchAtLogin.configureOnFirstRun(defaults: suite.reopen(), control: control)
        #expect(registered == 1)
        #expect(suite.defaults.bool(forKey: LaunchAtLogin.configuredKey))
    }

    @Test func turnedOffByUserStaysOff() {
        let suite = TestDefaults()
        suite.defaults.set(true, forKey: LaunchAtLogin.configuredKey)
        var calls = 0
        let control = LoginItemControl(isEnabled: { false }, setEnabled: { _ in calls += 1 })
        LaunchAtLogin.configureOnFirstRun(defaults: suite.defaults, control: control)
        #expect(calls == 0)
    }
}
