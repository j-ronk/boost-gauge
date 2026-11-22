import Foundation
import Testing
@testable import BoostGaugeKit

struct TempCatalogTests {
    /// Every flt temperature key an M1 Max (MacBookPro18,2) reported, 22 Nov 2026.
    static let m1MaxKeys: Set<String> = [
        "TAOL", "TB0T", "TB1T", "TB2T", "TC10", "TC11", "TC12", "TC13", "TC20", "TC21", "TC22", "TC23", "TC30", "TC31",
        "TC32", "TC33", "TC40", "TC41", "TC42", "TC43", "TC50", "TC51", "TC52", "TC53", "TCDX", "TCHP", "TCMb", "TCMz",
        "TD00", "TD01", "TD02", "TD03", "TD04", "TD10", "TD11", "TD12", "TD13", "TD14", "TD20", "TD21", "TD22", "TD23",
        "TD24", "TDBP", "TDCR", "TDEC", "TDEL", "TDER", "TDTP", "TDVx", "TDeL", "TDeR", "TH0a", "TH0b", "TH0x", "TH1a",
        "TH1b", "TMVR", "TPD0", "TPD1", "TPD2", "TPD3", "TPD4", "TPD5", "TPD6", "TPD7", "TPD8", "TPD9", "TPDX", "TPDa",
        "TPDb", "TPDc", "TPDd", "TPDe", "TPDf", "TPDg", "TPDh", "TPDi", "TPDj", "TPMP", "TPSP", "TPVD", "TRD0", "TRD1",
        "TRD2", "TRD3", "TRD4", "TRD5", "TRD6", "TRD7", "TRD8", "TRD9", "TRDX", "TRDa", "TRDb", "TRDc", "TRDd", "TRDe",
        "TRDf", "TRDg", "TRDh", "TRDi", "TRDj", "TS0P", "TSVR", "TSWR", "TSXR", "TVA0", "TVD0", "TVMD", "TVS0", "TVS1",
        "TVS2", "TVSx", "TVV0", "TW0P", "Ta00", "Ta01", "Ta02", "Ta04", "Ta05", "Ta06", "Ta08", "Ta09", "Ta0A", "Ta0C",
        "Ta0D", "Ta0E", "TaLP", "TaLT", "TaLW", "TaRF", "TaRT", "TaRW", "TaTP", "Td00", "Td01", "Td02", "Td04", "Td05",
        "Td06", "Td08", "Td09", "Td0A", "Td0C", "Td0D", "Td0E", "Td0G", "Td0H", "Td0I", "Td0K", "Td0L", "Td0M", "Te00",
        "Te01", "Te02", "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0S", "Tg0T", "Th00", "Th01", "Th02", "Th04",
        "Th05", "Th06", "Th08", "Th09", "Th0A", "Th0C", "Th0D", "Th0E", "Th0G", "Th0H", "Th0I", "Tm00", "Tm01", "Tm02",
        "Tm04", "Tm05", "Tm06", "Tm08", "Tm09", "Tm0A", "Tm0C", "Tm0D", "Tm0E", "Tp00", "Tp01", "Tp02", "Tp04", "Tp05",
        "Tp06", "Tp08", "Tp09", "Tp0A", "Tp0C", "Tp0D", "Tp0E", "Tp0G", "Tp0H", "Tp0I", "Tp0K", "Tp0L", "Tp0M", "Tp0O",
        "Tp0P", "Tp0Q", "Tp0S", "Tp0T", "Tp0U", "Tp0W", "Tp0X", "Tp0Y", "Tp0a", "Tp0b", "Tp0c", "Ts00", "Ts01", "Ts02",
        "Ts04", "Ts05", "Ts06", "Ts0P", "Ts1P", "Tz11", "Tz12", "Tz13", "Tz14", "Tz15", "Tz16", "Tz17", "Tz18", "Tz1j",
    ]

    static let m1Max = ChipInfo.parse(brand: "Apple M1 Max", efficiencyCores: 2, totalCores: 10)

    @Test func parsesBrandStrings() {
        #expect(Self.m1Max == ChipInfo(family: .m(1), tier: .max, efficiencyCores: 2, totalCores: 10))
        #expect(ChipInfo.parse(brand: "Apple M4 Pro", efficiencyCores: 4, totalCores: 14).tier == .pro)
        #expect(ChipInfo.parse(brand: "Apple M2 Ultra", efficiencyCores: 8, totalCores: 24).family == .m(2))
        #expect(ChipInfo.parse(brand: "Apple M3", efficiencyCores: 4, totalCores: 8).tier == .base)
        let a18 = ChipInfo.parse(brand: "Apple A18 Pro", efficiencyCores: 4, totalCores: 6)
        #expect(a18.family == .a18Pro && a18.tier == .base)
        #expect(ChipInfo.parse(brand: "Intel(R) Core(TM) i9", efficiencyCores: 0, totalCores: 8).family == nil)
    }

    @Test func m1MaxNamesAndGroups() {
        let entries = TempCatalog.entries(present: Self.m1MaxKeys, chip: Self.m1Max)
        func names(_ g: TempGroup) -> [String] { entries.filter { $0.group == g }.map(\.name) }
        #expect(names(.cpu) == (1...8).map { "Performance core \($0)" } + ["Efficiency core 1", "Efficiency core 2"])
        #expect(entries.first { $0.name == "Efficiency core 1" }?.key == "Tp09")
        #expect(entries.first { $0.name == "Efficiency core 2" }?.key == "Tp0T")
        #expect(names(.gpu) == ["GPU 1", "GPU 2", "GPU 3", "GPU 4"])
        #expect(names(.memory) == ["Memory 1", "Memory 2", "Memory 3", "Memory 4"])
        #expect(names(.ssd) == ["SSD"])
        // TB0T reads as the hotter cell, so it's left out beside TB1T and TB2T.
        #expect(names(.battery) == ["Battery 1", "Battery 2"])
        #expect(names(.airflow) == ["Left", "Right"])
        #expect(names(.wireless) == ["Wi-Fi"])
        // Nothing unnamed slips in.
        #expect(!entries.contains { ["TC10", "TPD0", "Ts0P", "TCHP", "Tp02"].contains($0.key) })
    }

    @Test func coreNamesNeedMatchingCoreCounts() {
        // Same keys, but macOS says 4 efficiency cores: the M1 Max labels can't be right, so no P/E labels.
        let wrong = ChipInfo(family: .m(1), tier: .base, efficiencyCores: 4, totalCores: 8)
        let cpu = TempCatalog.entries(present: Self.m1MaxKeys, chip: wrong).filter { $0.group == .cpu }
        #expect(!cpu.isEmpty)
        #expect(cpu.allSatisfy { $0.name.hasPrefix("CPU die ") })
        #expect(cpu.map(\.name) == (1...cpu.count).map { "CPU die \($0)" })

        let unknown = TempCatalog.entries(present: ["Tp01", "Tp05", "Tg05", "TB0T"], chip: ChipInfo(family: nil))
        #expect(unknown.map(\.name) == ["CPU die 1", "CPU die 2", "GPU 1", "Battery"])
    }

    @Test func m4GPUKeysFollowTier() {
        let base = ChipInfo(family: .m(4), tier: .base), max = ChipInfo(family: .m(4), tier: .max)
        let keys: Set<String> = ["Tg0G", "Tg1U", "Tg0K"]
        #expect(TempCatalog.entries(present: keys, chip: base).filter { $0.group == .gpu }.map(\.key) == ["Tg0G", "Tg0K"])
        #expect(TempCatalog.entries(present: keys, chip: max).filter { $0.group == .gpu }.map(\.key) == ["Tg1U", "Tg0K"])
    }

    @Test func candidatesCoverEveryEntryOnce() {
        let candidates = TempCatalog.candidateKeys(Self.m1Max)
        #expect(Set(candidates).count == candidates.count)
        let entries = TempCatalog.entries(present: Self.m1MaxKeys, chip: Self.m1Max)
        #expect(entries.allSatisfy { candidates.contains($0.key) })
    }

    @Test func hidSensorsKeepHottestCopyAndDropBogus() {
        let rows = TempCatalog.hidSensors([
            ("gas gauge battery", 32.0), ("gas gauge battery", 32.5), ("gas gauge battery", 0),
            ("PMU tdie10", 44.6), ("PMU tdie1", 44.3), ("PMU tdie1", 44.9), ("PMU tdie0", 127),
            ("PMU tdev1", 42.9), ("PMU tcal", 51.9), ("NAND CH0 temp", 31),
        ], skipSSD: false)
        #expect(rows.map(\.group) == [.ssd, .battery, .powerManager, .powerManager])
        #expect(rows.map(\.sensor) == [TempSensor("SSD", 31), TempSensor("Gas gauge", 32.5),
                                       TempSensor("Die sensor 1", 44.9), TempSensor("Die sensor 2", 44.6)])
        #expect(!TempCatalog.hidSensors([("NAND CH0 temp", 31)], skipSSD: true).contains { $0.group == .ssd })
    }

    @Test func groupingDropsEmptyAndBogus() {
        let groups = TempCatalog.group([
            (.wireless, TempSensor("Wi-Fi", 45)), (.cpu, TempSensor("A", 60)), (.cpu, TempSensor("B", 70)),
            (.cpu, TempSensor("C", 0)), (.gpu, TempSensor("GPU 1", -4)), (.memory, TempSensor("M", 130)),
        ])
        #expect(groups.map(\.group) == [.cpu, .wireless])
        #expect(groups[0].sensors.map(\.name) == ["A", "B"])
        #expect(groups[0].average == 65)
        #expect(groups[0].hottest == TempSensor("B", 70))
        #expect(TempCatalog.isValid(126.9) && !TempCatalog.isValid(127) && !TempCatalog.isValid(0))
    }

    @Test func everyGroupHasItsOwnTempsSection() {
        let sections = TempGroup.allCases.map(\.section)
        #expect(Set(sections).count == TempGroup.allCases.count)
        #expect(sections.allSatisfy { $0.item == .temps })
        #expect(PanelSectionID.sections(of: .temps).map(\.title)
            == ["CPU", "GPU", "Memory", "SSD", "Battery", "Power Manager", "Airflow", "Wi-Fi", "Fans"])
    }
}
