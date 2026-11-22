import Foundation
import Testing
@testable import VitalsKit

struct ProcessSamplerTests {
    @Test func topSkipsNewPids() {
        let previous = [ProcessCPUTime(pid: 1, name: "a", cpuNanos: 0)]
        let current = [ProcessCPUTime(pid: 1, name: "a", cpuNanos: 100_000_000),
                       ProcessCPUTime(pid: 2, name: "new", cpuNanos: 9_000_000_000)]
        let top = ProcessSampler.top(previous: previous, current: current, elapsed: 1, n: 3)
        #expect(top.map(\.name) == ["a"])
        #expect(abs(top[0].percent - 10) < 0.001)
    }

    @Test func topOrdersDescending() {
        let previous = (1...5).map { ProcessCPUTime(pid: pid_t($0), name: "p\($0)", cpuNanos: 0) }
        let current = [ProcessCPUTime(pid: 1, name: "p1", cpuNanos: 200_000_000),
                       ProcessCPUTime(pid: 2, name: "p2", cpuNanos: 1_600_000_000),
                       ProcessCPUTime(pid: 3, name: "p3", cpuNanos: 0),
                       ProcessCPUTime(pid: 4, name: "p4", cpuNanos: 800_000_000),
                       ProcessCPUTime(pid: 5, name: "p5", cpuNanos: 400_000_000)]
        let top = ProcessSampler.top(previous: previous, current: current, elapsed: 2, n: 3)
        #expect(top.map(\.name) == ["p2", "p4", "p5"])
        #expect(top.map(\.pid) == [2, 4, 5])
        #expect(top.map(\.percent) == [80, 40, 20])
    }

    @Test func reusedPidWithLowerTimeIsSkipped() {
        let previous = [ProcessCPUTime(pid: 7, name: "old", cpuNanos: 5_000_000_000)]
        let current = [ProcessCPUTime(pid: 7, name: "new", cpuNanos: 1_000)]
        #expect(ProcessSampler.top(previous: previous, current: current, elapsed: 1, n: 3).isEmpty)
    }

    @Test func zeroElapsedGivesNothing() {
        let p = [ProcessCPUTime(pid: 1, name: "a", cpuNanos: 0)]
        let c = [ProcessCPUTime(pid: 1, name: "a", cpuNanos: 10)]
        #expect(ProcessSampler.top(previous: p, current: c, elapsed: 0, n: 3).isEmpty)
    }

    @Test func winnersWithoutNamesAreLookedUp() {
        let me = getpid()
        let top = ProcessSampler.top(previous: [ProcessCPUTime(pid: me, name: "", cpuNanos: 0)],
                                     current: [ProcessCPUTime(pid: me, name: "", cpuNanos: 1_000)], elapsed: 1, n: 3)
        #expect(top.first?.name.isEmpty == false)
    }

    @Test func snapshotSeesThisProcess() {
        let me = getpid()
        #expect(ProcessSampler.snapshot().contains { $0.pid == me && $0.cpuNanos > 0 })
        #expect(ProcessSampler.footprints().contains { $0.pid == me && $0.bytes > 0 })
    }
}
