import Foundation
import Testing
@testable import VitalsKit

/// clients-a/b.plist: this Mac's IOAccelerator user clients (`ioreg -a -l`, trimmed to the read keys), recorded 2.09 s apart.
struct GPUClientsTests {
    private func clients(_ name: String) throws -> [[String: Any]] {
        try #require(Fixture.plist("GPU/\(name).plist") as? [[String: Any]])
    }

    @Test func parsesCreator() {
        #expect(GPUClients.creator("pid 176, WindowServer")! == (176, "WindowServer"))
        #expect(GPUClients.creator("pid 3328, Bionic Helper")! == (3328, "Bionic Helper"))
        #expect(GPUClients.creator("pid 12, name, with comma")! == (12, "name, with comma"))
        #expect(GPUClients.creator("pid x, Foo") == nil)
        #expect(GPUClients.creator("WindowServer") == nil)
        #expect(GPUClients.creator("") == nil)
    }

    @Test func sumsGPUTimePerPid() throws {
        let time = GPUClients.gpuTime(try clients("clients-a"))
        #expect(time.count == 46)
        // WindowServer holds two user clients, one with two Metal queues; all three add up.
        #expect(time[176] == 342_579_448_749)
        // A client with an empty AppUsage still counts, at zero, so a pid that starts drawing has a baseline.
        #expect(time[441] == 0)
    }

    @Test func skipsMalformedClients() {
        let clients: [[String: Any]] = [
            [:],
            ["IOUserClientCreator": "nonsense", "AppUsage": [["accumulatedGPUTime": 5]]],
            ["IOUserClientCreator": "pid 9, Foo", "AppUsage": "not an array"],
            ["IOUserClientCreator": "pid 9, Foo", "AppUsage": [["API": "Metal"], ["accumulatedGPUTime": 7]]],
        ]
        #expect(GPUClients.gpuTime(clients) == [9: 7])
    }

    @Test func deltaOverWallTimeIsPercent() throws {
        let a = GPUClients.gpuTime(try clients("clients-a"))
        let b = GPUClients.gpuTime(try clients("clients-b"))
        // accumulatedGPUTime is nanoseconds: the busiest client, WindowServer, comes to 4.4% over 2 s, close to
        // the 0-19% Device Utilization ioreg showed at the time.
        let percent = GPUClients.percents(previous: a, current: b, elapsed: 2)
        #expect(abs(percent[176]! - 4.440) < 0.001)
        #expect(abs(percent[2493]! - 1.867) < 0.001)
        #expect(percent[182] == nil)
    }

    @Test func newExitedAndShrinkingPidsAreDropped() {
        // A new pid's total covers its whole life, not the interval; a shrinking total means a client closed.
        let percent = GPUClients.percents(previous: [1: 100, 2: 1_000_000_000, 3: 5], current: [1: 500_000_100, 2: 10, 4: 900], elapsed: 1)
        #expect(percent == [1: 50])
        #expect(GPUClients.percents(previous: [1: 0], current: [1: 1_000], elapsed: 0).isEmpty)
    }

    @Test func percentIsCappedAtFull() {
        // Concurrent queues can add up to more GPU time than wall time.
        #expect(GPUClients.percents(previous: [1: 0], current: [1: 3_000_000_000], elapsed: 1) == [1: 100])
    }

    @Test func groupsByAppAndOmitsIdle() {
        let percent: [pid_t: Double] = [10: 3, 11: 2.6, 20: 4, 30: 0.4, 40: 1, 50: 0.2]
        let key: (pid_t) -> String = { [10: "Safari", 11: "Safari", 20: "WindowServer", 30: "Crisp", 40: "Herdr", 50: "Herdr"][$0]! }
        let top = GPUClients.top(percent, key: key, n: 3)
        #expect(top.map(\.key) == ["Safari", "WindowServer", "Herdr"])
        // The busiest process stands in for the app's name and icon.
        #expect(top.map(\.pid) == [10, 20, 40])
        #expect(abs(top[0].percent - 5.6) < 1e-9)
        #expect(abs(top[2].percent - 1.2) < 1e-9)
        // Crisp rounds to 0%, so it isn't shown at all.
        #expect(GPUClients.top(percent, key: key, n: 5).map(\.key) == ["Safari", "WindowServer", "Herdr"])
        #expect(GPUClients.top([1: 0.3], key: { _ in "a" }, n: 3).isEmpty)
    }

    @Test func tiesBreakByKey() {
        let top = GPUClients.top([1: 2, 2: 2], key: { $0 == 1 ? "b" : "a" }, n: 3)
        #expect(top.map(\.key) == ["a", "b"])
    }

    @Test func readsThisMac() {
        // WindowServer always has a Metal client.
        #expect(GPUClients.gpuTime(GPUClients.read()).count > 0)
    }
}
