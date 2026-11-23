import Foundation
import Testing
@testable import BoostGaugeKit

struct HistoryTierTests {
    @Test func bucketKeepsRunningAverageAndPeak() {
        var tier = HistoryTier(bucket: 5, capacity: 10)
        tier.add(10, at: 100)
        tier.add(30, at: 102)
        tier.add(50, at: 106)
        #expect(tier.points(from: 0, to: 110) == [ChartPoint(t: 102.5, avg: 20, peak: 30),
                                                  ChartPoint(t: 107.5, avg: 50, peak: 50)])
    }

    @Test func skippedBucketsAreGapsAndTheRingForgetsOldOnes() {
        var tier = HistoryTier(bucket: 1, capacity: 4)
        for t in 0..<4 { tier.add(Float(t + 1), at: TimeInterval(t)) }
        tier.add(9, at: 6)
        // Buckets 4 and 5 had no reading; 0 to 2 have rolled out of the ring.
        #expect(tier.points(from: 0, to: 7).map(\.avg) == [4, 9])
        #expect(tier.points(from: 0, to: 7).map(\.t) == [3.5, 6.5])
        tier.add(1, at: 100)
        #expect(tier.points(from: 0, to: 101).map(\.avg) == [1])
    }

    @Test func clockSteppingBackIsDroppedOrRestarts() {
        var tier = HistoryTier(bucket: 1, capacity: 4)
        tier.add(5, at: 10)
        tier.add(7, at: 9)
        #expect(tier.points(from: 0, to: 11).map(\.avg) == [5])
        tier.add(3, at: -20)
        #expect(tier.points(from: -30, to: 11).map(\.avg) == [3])
    }

    @Test func pointsAreClampedToTheWindowEnd() {
        var tier = HistoryTier(bucket: 60, capacity: 10)
        tier.add(1, at: 6000)
        #expect(tier.points(from: 5000, to: 6010).map(\.t) == [6010])
    }
}

@MainActor
struct SeriesHistoryTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 600_000)

    @Test func readingsRollUpIntoEveryTier() {
        let s = SeriesHistory()
        for i in 0..<60 { s.record(Double(i), at: t0.addingTimeInterval(Double(i))) }
        #expect(s.tiers[0].points(from: 0, to: 1e9).count == 60)
        let fives = s.tiers[1].points(from: 0, to: 1e9)
        #expect(fives.count == 12)
        #expect(fives[0].avg == 2 && fives[0].peak == 4)
        let minute = s.tiers[2].points(from: 0, to: 1e9)
        #expect(minute.map(\.avg) == [29.5])
        #expect(minute.map(\.peak) == [59])
        #expect(s.revision == 60)
    }

    @Test func eachRangeReadsItsOwnTier() {
        let s = SeriesHistory()
        for i in 0..<7200 where i % 2 == 0 { s.record(10, at: t0.addingTimeInterval(Double(i))) }
        let now = t0.addingTimeInterval(7199)
        #expect(s.points(.tenMinutes, now: now).count == 300)
        // 720 five-second buckets thin to about one per column.
        #expect((200...240).contains(s.points(.hour, now: now).count))
        #expect(s.points(.day, now: now).count == 120)
    }

    @Test func theSameMomentReadTwiceCountsOnce() {
        let s = SeriesHistory()
        s.record(10, at: t0)
        s.record(90, at: t0.addingTimeInterval(0.2))
        s.record(.nan, at: t0.addingTimeInterval(2))
        #expect(s.revision == 1)
        #expect(s.points(.tenMinutes, now: t0.addingTimeInterval(3)).map(\.avg) == [10])
    }

    @Test func dayThinsToAboutOnePointPerColumnAndKeepsThePeak() {
        let s = SeriesHistory()
        for m in 0..<1440 { s.record(m == 700 ? 100 : 10, at: t0.addingTimeInterval(Double(m * 60))) }
        let now = t0.addingTimeInterval(1439 * 60)
        let slice = s.slice(.day, now: now)
        #expect(slice.points.count <= ChartLayout.columns)
        #expect(slice.points.count >= ChartLayout.columns - 2)
        #expect(slice.spacing == 360)
        #expect(slice.points.map(\.peak).max() == 100)
        #expect(slice.points.map(\.avg).max()! < 100)
        // A sparse day isn't thinned, so its points stay a minute apart.
        let sparse = SeriesHistory()
        sparse.record(1, at: t0)
        #expect(sparse.slice(.day, now: t0).spacing == 60)
    }

    @Test func aGapSplitsTheLine() {
        let s = SeriesHistory()
        for m in 0..<60 { s.record(5, at: t0.addingTimeInterval(Double(m * 60))) }
        for m in 180..<240 { s.record(5, at: t0.addingTimeInterval(Double(m * 60))) }
        let now = t0.addingTimeInterval(240 * 60)
        let slice = s.slice(.day, now: now)
        let runs = ChartLine.runs(slice.points, gap: slice.spacing * ChartLayout.gapFactor)
        #expect(runs.map(\.count) == [60, 60])
    }

    @Test func thinningLeavesFewPointsAlone() {
        let few = (0..<10).map { ChartPoint(t: Double($0), avg: 1, peak: 1) }
        #expect(SeriesHistory.thin(few, from: 0, to: 10, columns: 5) == few)
    }
}

@MainActor
struct ChartHistoryTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 600_000)

    /// Two hours of readings with an hour off in the middle.
    private func dayWithAGap() -> (ChartHistory, Date) {
        let h = ChartHistory()
        for m in 0..<180 where !(60..<120).contains(m) {
            h.record(.cpu, Double(m % 50), at: t0.addingTimeInterval(Double(m * 60)))
            h.record(.networkDown, Double(m * 1000), at: t0.addingTimeInterval(Double(m * 60)))
        }
        return (h, t0.addingTimeInterval(180 * 60))
    }

    @Test func seriesAreMadeOnFirstUseSoUnseenItemsCostNothing() {
        let h = ChartHistory()
        #expect(h.recordedSeries.isEmpty)
        h.record(.gpu, nil, at: t0)
        #expect(h.recordedSeries.isEmpty)
        h.record(.gpu, 40, at: t0)
        #expect(h.recordedSeries == [.gpu])
        #expect(h(.gpu) === h(.gpu))
    }

    @Test func savedDayComesBackWithItsGap() {
        let (h, now) = dayWithAGap()
        let restored = ChartHistory()
        restored.decode(try! h.encoded())
        for id in [ChartSeriesID.cpu, .networkDown] {
            let day = restored(id).points(.day, now: now)
            #expect(day == h(id).points(.day, now: now))
            #expect(day.count == 120)
            #expect(!day.contains { $0.t > t0.timeIntervalSinceReferenceDate + 3600 && $0.t < t0.timeIntervalSinceReferenceDate + 7200 })
        }
        // Only the day is saved: 10 Min and 1 Hour start fresh.
        #expect(restored(.cpu).points(.tenMinutes, now: now).isEmpty)
        #expect(restored(.cpu).points(.hour, now: now).isEmpty)
        #expect(restored.recordedSeries == [.cpu, .networkDown])
    }

    @Test func relaunchInsideAMinuteKeepsItsAverage() {
        let h = ChartHistory()
        h.record(.cpu, 10, at: t0)
        let restored = ChartHistory()
        restored.decode(try! h.encoded())
        restored.record(.cpu, 30, at: t0.addingTimeInterval(10))
        let day = restored(.cpu).points(.day, now: t0.addingTimeInterval(20))
        #expect(day.map(\.avg) == [20])
        #expect(day.map(\.peak) == [30])
    }

    @Test func unreadableOrOtherVersionStartsEmpty() throws {
        let (h, now) = dayWithAGap()
        let garbage = ChartHistory()
        garbage.decode(Data("not a plist".utf8))
        #expect(garbage.recordedSeries.isEmpty)

        var dict = try #require(PropertyListSerialization.propertyList(from: h.encoded(), format: nil) as? [String: Any])
        dict["version"] = 2
        let future = ChartHistory()
        future.decode(try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0))
        #expect(future.recordedSeries.isEmpty)

        dict["version"] = 1
        dict["bucket"] = 30.0
        let otherBucket = ChartHistory()
        otherBucket.decode(try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0))
        #expect(otherBucket(.cpu).points(.day, now: now).isEmpty)
    }

    @Test func savesToAndLoadsFromAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("BoostGauge/charts-24h.plist")

        let nothing = ChartHistory()
        nothing.save()
        nothing.load(from: url)
        nothing.save()
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing recorded, nothing written")

        let (h, now) = dayWithAGap()
        h.load(from: url)
        h.save()
        let relaunched = ChartHistory()
        relaunched.load(from: url)
        #expect(relaunched(.cpu).points(.day, now: now) == h(.cpu).points(.day, now: now))
        #expect(try Data(contentsOf: url).count < 30_000)
    }

    @Test func defaultFileLivesInApplicationSupport() {
        let url = ChartHistory.defaultURL
        #expect(url.lastPathComponent == "charts-24h.plist")
        #expect(url.deletingLastPathComponent().lastPathComponent == "BoostGauge")
        #expect(url.path.contains("Application Support"))
    }

    @Test func storedNamesNeverChange() {
        #expect(ChartRange.allCases.map(\.rawValue) == ["10m", "1h", "24h"])
        #expect(ChartRange.allCases.map(\.title) == ["10 Min", "1 Hour", "24 Hours"])
        #expect(ChartSeriesID.cpu.rawValue == "cpu.usage")
        #expect(ChartSeriesID.powerBattery.rawValue == "power.battery")
        #expect(Set(ChartSeriesID.allCases.map(\.rawValue)).count == ChartSeriesID.allCases.count)
    }
}

@MainActor
struct ChartRangeSettingTests {
    @Test func oneRangeSharedAndRemembered() {
        let suite = TestDefaults()
        let settings = AppSettings(defaults: suite.defaults)
        #expect(settings.chartRange == .tenMinutes)
        settings.chartRange = .day
        #expect(suite.defaults.string(forKey: "chart.range") == "24h")
        #expect(AppSettings(defaults: suite.reopen()).chartRange == .day)
    }

    @Test func unknownStoredRangeFallsBackToTenMinutes() {
        let suite = TestDefaults()
        suite.defaults.set("7d", forKey: "chart.range")
        #expect(AppSettings(defaults: suite.reopen()).chartRange == .tenMinutes)
    }
}

struct ChartScaleTests {
    @Test func niceTopsHalveToPlainNumbers() {
        #expect(ChartScale.nice(0) == 1)
        #expect(ChartScale.nice(13) == 20)
        #expect(ChartScale.nice(45) == 60)
        #expect(ChartScale.nice(100) == 100)
        #expect(ChartScale.nice(1_100_000) == 2_000_000)
    }

    @Test func floorKeepsIdleFromLookingNoisy() {
        let idle = ChartScale.upward([3, 5], floor: 20) { "\(Int($0))W" }
        #expect(idle.hi == 20)
        #expect(idle.labels.map(\.text) == ["0W", "10W", "20W"])
        #expect(ChartScale.upward([], floor: 20) { "\($0)" }.hi == 20)
        #expect(ChartScale.upward([31], floor: 20) { "\($0)" }.hi == 40)
    }

    @Test func temperaturesGetRoundTensAround() {
        let s = ChartScale.temperature([55, 72])
        #expect(s.labels.map(\.text) == ["40°", "60°", "80°"])
        #expect(ChartScale.temperature([]).hi - ChartScale.temperature([]).lo >= 20)
        #expect(ChartScale.percent.labels.map(\.text) == ["0%", "50%", "100%"])
    }
}

struct ChartTimeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func alwaysThreeLabelsInsideThePlot() {
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for span in [600.0, 3600, 86_400, 864_000] {
            for step in stride(from: 0.0, to: span, by: span / 37) {
                let end = base.addingTimeInterval(step)
                let start = end.addingTimeInterval(-span)
                let ticks = ChartTime.ticks(from: start, to: end, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
                #expect(ticks.count == 3, "span \(span) at \(step)")
                #expect(ticks.allSatisfy { $0.t > start.timeIntervalSinceReferenceDate && $0.t < end.timeIntervalSinceReferenceDate })
            }
        }
    }

    @Test func runsSplitWhereReadingsStop() {
        let points = [0.0, 2, 4, 200, 202].map { ChartPoint(t: $0, avg: 1, peak: 1) }
        #expect(ChartLine.runs(points, gap: 10).map(\.count) == [3, 2])
        #expect(ChartLine.runs([], gap: 10).isEmpty)
        let line = ChartLine(name: "x", runs: ChartLine.runs(points, gap: 10))
        #expect(line.value(near: 2.4, within: 5)?.t == 2)
        #expect(line.value(near: 100, within: 5) == nil)
    }
}

/// The `--render` sample day feeds the README, so it must repeat exactly and end on the panels' header figures.
@MainActor
struct ChartSamplesTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func sameRenderEveryRun() {
        let a = ChartSamples.make(now: now), b = ChartSamples.make(now: now)
        for id in ChartSeriesID.allCases {
            #expect(a(id).points(.day, now: now) == b(id).points(.day, now: now), "\(id)")
        }
    }

    @Test func endsOnTheHeaderFigures() {
        let h = ChartSamples.make(now: now)
        let figures: [(ChartSeriesID, Float)] = [(.cpu, 23), (.gpu, 100), (.memoryUsed, 49), (.tempsHottest, 72),
                                                 (.diskRead, 12_300_000), (.powerSystem, 18.2)]
        for (id, value) in figures {
            #expect(h(id).points(.tenMinutes, now: now).last?.avg == value, "\(id)")
        }
    }

    @Test func everyRangeHasALineAndTheDayHasTheOvernightGap() {
        let h = ChartSamples.make(now: now)
        for id in ChartSeriesID.allCases {
            // The 10 Min ring holds the last 600 seconds: 300 readings two seconds apart.
            #expect(h(id).points(.tenMinutes, now: now).count == 300, "\(id)")
            let day = h(id).slice(.day, now: now)
            let runs = ChartLine.runs(day.points, gap: day.spacing * ChartLayout.gapFactor)
            #expect(runs.count == 2, "\(id)")
            let n = now.timeIntervalSinceReferenceDate
            #expect(!day.points.contains { $0.t > n - 8.9 * 3600 && $0.t < n - 7.1 * 3600 })
        }
    }

    @Test func mostlyCalmWithBursts() {
        let v = ChartSamples.make(now: now)(.cpu).points(.hour, now: now).map(\.avg).sorted()
        #expect(v[v.count / 2] < 30, "median is everyday use")
        #expect(v.last! > 40, "bursts")
    }
}

struct MemoryPressureTests {
    @Test func readsThisMac() {
        let p = MemoryPressure.percent()
        #expect(p.map { (0...100).contains($0) } ?? true)
    }
}
