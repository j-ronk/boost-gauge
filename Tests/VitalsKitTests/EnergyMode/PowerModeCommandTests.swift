import Foundation
import Testing
@testable import VitalsKit

struct PowerModeCommandTests {
    @Test func batteryLow() {
        #expect(PowerModeCommand(rawSource: 0, rawMode: 1)?.arguments == ["-b", "powermode", "1"])
    }

    @Test func adapterHigh() {
        #expect(PowerModeCommand(rawSource: 1, rawMode: 2)?.arguments == ["-c", "powermode", "2"])
    }

    @Test(arguments: [(2, 0), (0, 3), (0, -1), (-1, 0), (1, 99), (Int.max, Int.min)])
    func outOfRangeIsNil(source: Int, mode: Int) {
        #expect(PowerModeCommand(rawSource: source, rawMode: mode) == nil)
    }

    @Test func neverAll() {
        var built = 0
        for source in -2...3 {
            for mode in -2...4 {
                guard let command = PowerModeCommand(rawSource: source, rawMode: mode) else { continue }
                built += 1
                #expect(!command.arguments.contains("-a"))
                #expect(command.arguments.count == 3)
                #expect(command.arguments[1] == "powermode")
            }
        }
        #expect(built == 6)
    }

    @Test func executableIsSystemPmset() {
        #expect(PowerModeCommand.executable == "/usr/bin/pmset")
    }

    @Test func typedInitMatchesRaw() {
        #expect(PowerModeCommand(source: .battery, mode: .automatic) == PowerModeCommand(rawSource: 0, rawMode: 0))
        #expect(PowerModeCommand(source: .adapter, mode: .low).arguments == ["-c", "powermode", "1"])
    }
}

struct PmsetCustomParserTests {
    @Test func recordedFixture() {
        let modes = PmsetCustomParser.modes(Fixture.string("EnergyMode/pmset-custom.txt"))
        #expect(modes == [.battery: .automatic, .adapter: .high])
    }

    @Test func noPowermodeLines() {
        #expect(PmsetCustomParser.modes(Fixture.string("EnergyMode/pmset-custom-no-powermode.txt")).isEmpty)
    }

    @Test func emptyOutput() {
        #expect(PmsetCustomParser.modes("").isEmpty)
    }

    @Test func blockOrderAndUPSIgnored() {
        let out = """
        AC Power:
         powermode            1
        UPS Power:
         powermode            2
        Battery Power:
         lowpowermode         0
         powermode            2
        """
        #expect(PmsetCustomParser.modes(out) == [.adapter: .low, .battery: .high])
    }

    @Test func unknownModeValueSkipped() {
        let out = "Battery Power:\n powermode 7\nAC Power:\n powermode 0\n"
        #expect(PmsetCustomParser.modes(out) == [.adapter: .automatic])
    }
}
