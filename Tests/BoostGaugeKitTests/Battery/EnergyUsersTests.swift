import Foundation
import Testing
@testable import BoostGaugeKit

struct EnergyUsersTests {
    @Test func usesSecondSample() throws {
        let rows = EnergyUsers.parseTop(Fixture.string("Battery/top-sample.txt"))
        let first = try #require(rows.first)
        #expect(first.pid == 984)
        #expect(first.command == "opencode")
        #expect(first.power == 131.7)
        #expect(rows.count == 29)
        #expect(!rows.contains { $0.command == "top" })
        #expect(rows.contains { $0.command == "Bionic Helper (R" && $0.power == 0.9 })
    }

    @Test func emptyOrGarbage() {
        #expect(EnergyUsers.parseTop("").isEmpty)
        #expect(EnergyUsers.parseTop("PID COMMAND POWER\nnope\n").isEmpty)
    }

    @Test func helpersRollUp() {
        let rows: [(pid: pid_t, command: String, power: Double)] = [
            (1, "Google Chrome", 10), (2, "Google Chrome He", 5.5), (3, "Google Chrome He", 2), (4, "Mail", 3),
        ]
        let users = EnergyUsers.rollup(rows) { pid in
            pid == 4 ? ("/System/Applications/Mail.app", "Mail") : ("/Applications/Google Chrome.app", "Google Chrome")
        }
        #expect(users.map(\.name) == ["Google Chrome", "Mail"])
        #expect(users[0].power == 17.5)
    }

    @Test func topFive() {
        let rows: [(pid: pid_t, command: String, power: Double)] = (1...7).map { (pid_t($0), "p\($0)", Double($0)) }
            + [(8, "idle", 0)]
        let users = EnergyUsers.rollup(rows) { ("k\($0)", "p\($0)") }
        #expect(users.map(\.name) == ["p7", "p6", "p5", "p4", "p3"])
    }
}
