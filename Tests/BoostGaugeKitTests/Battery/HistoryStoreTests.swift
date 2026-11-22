import Foundation
import Testing
@testable import BoostGaugeKit

/// A fresh history file per test, removed afterwards.
final class TempHistory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("boostgauge-history-\(UUID().uuidString)")
            .appendingPathComponent("battery-history.csv")
    }
    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func lines() -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
    deinit { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

struct HistoryStoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func appendAndReload() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        #expect(!store.fileExists)
        store.append(ChargeSample(date: now.addingTimeInterval(-600), percent: 40, charging: true))
        store.append(ChargeSample(date: now, percent: 41, charging: true))
        #expect(store.fileExists)
        #expect(tmp.lines() == ["1799999400,40,1", "1800000000,41,1"])

        let reloaded = HistoryStore(url: tmp.url)
        #expect(reloaded.samples.map(\.percent) == [40, 41])
        let series = reloaded.series(.day, now: now)
        #expect(series.count == 1)
        #expect(series[0].map(\.percent) == [40, 41])
    }

    @Test func compactKeepsTenDays() throws {
        let tmp = TempHistory()
        let old = Int(now.timeIntervalSince1970) - 11 * 86_400
        let recent = Int(now.timeIntervalSince1970) - 1 * 86_400
        try tmp.write("\(old),90,0\n\(recent),50,1\n")
        let store = HistoryStore(url: tmp.url)
        store.compact(now: now)
        #expect(store.samples.map(\.percent) == [50])
        #expect(tmp.lines() == ["\(recent),50,1"])
    }

    @Test func gapStartsNewSegment() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        let start = now.addingTimeInterval(-6 * 3600)
        for m in 0..<30 { store.append(ChargeSample(date: start.addingTimeInterval(Double(m) * 60), percent: 80 - m / 3, charging: false)) }
        let afterGap = start.addingTimeInterval(30 * 60 + 3 * 3600)
        for m in 0..<30 { store.append(ChargeSample(date: afterGap.addingTimeInterval(Double(m) * 60), percent: 60 + m / 3, charging: true)) }
        let day = store.series(.day, now: now)
        #expect(day.count == 2)
        // 30 one-minute samples fall into 6 or 7 five-minute buckets.
        #expect((6...7).contains(day[0].count))
        #expect(store.series(.tenDays, now: now).count == 2)
    }

    @Test func bucketKeepsLastSample() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        let bucketStart = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 300).rounded(.down) * 300 - 3600)
        store.append(ChargeSample(date: bucketStart, percent: 10, charging: true))
        store.append(ChargeSample(date: bucketStart.addingTimeInterval(120), percent: 11, charging: true))
        store.append(ChargeSample(date: bucketStart.addingTimeInterval(240), percent: 12, charging: true))
        #expect(store.series(.day, now: now) == [[ChargeSample(date: bucketStart.addingTimeInterval(240), percent: 12, charging: true)]])
    }

    @Test func rangeExcludesOlder() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        store.append(ChargeSample(date: now.addingTimeInterval(-2 * 86_400), percent: 70, charging: false))
        store.append(ChargeSample(date: now.addingTimeInterval(-3600), percent: 60, charging: false))
        #expect(store.series(.day, now: now).flatMap { $0 }.map(\.percent) == [60])
        #expect(store.series(.tenDays, now: now).flatMap { $0 }.map(\.percent) == [70, 60])
    }

    /// pmset-seeded history is sparse (a reading every 10–60 min while awake). At its real spacing, awake stretches
    /// stay joined and only the sleeps (3.4 h, 7.5 h, 10 h here) break the line; the lone 07:15 reading gets a dot.
    @Test func seededSpacingStaysConnected() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        let samples = PmsetLogParser.chargeSamples(Fixture.string("Battery/pmset-log-sample.txt"))
        store.seed(samples)
        let end = samples.last!.date
        let segments = store.series(.tenDays, now: end)
        #expect(segments.map(\.count) == [3, 2, 1, 2])
    }

    @Test func truncatedLastLineDoesNotSwallowNextSample() throws {
        let tmp = TempHistory()
        let t = Int(now.timeIntervalSince1970)
        try tmp.write("\(t - 120),50,1\n\(t - 60),5")
        let store = HistoryStore(url: tmp.url)
        store.append(ChargeSample(date: now, percent: 52, charging: true))
        #expect(HistoryStore(url: tmp.url).samples.map(\.percent) == [50, 52])
    }

    @Test func corruptLineSkipped() throws {
        let tmp = TempHistory()
        let t = Int(now.timeIntervalSince1970)
        try tmp.write("\(t - 120),50,1\ngarbage\n\(t - 60),abc,1\n\(t - 30),150,1\n,,\n\(t),51,0\n")
        let store = HistoryStore(url: tmp.url)
        #expect(store.samples.map(\.percent) == [50, 51])
        #expect(store.samples.map(\.charging) == [true, false])
    }

    @Test func emptyStoreEmptySeries() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        #expect(store.series(.day, now: now).isEmpty)
        #expect(store.series(.tenDays, now: now).isEmpty)
        store.compact(now: now)
        #expect(!store.fileExists)
    }

    @Test func seedMergesInOrder() {
        let tmp = TempHistory()
        let store = HistoryStore(url: tmp.url)
        store.append(ChargeSample(date: now, percent: 30, charging: false))
        store.seed([ChargeSample(date: now.addingTimeInterval(-7200), percent: 35, charging: false),
                    ChargeSample(date: now.addingTimeInterval(-3600), percent: 33, charging: false)])
        #expect(store.samples.map(\.percent) == [35, 33, 30])
        #expect(HistoryStore(url: tmp.url).samples.map(\.percent) == [35, 33, 30])
    }

    @Test func rangeTitles() {
        #expect(HistoryRange.day.title == "24 Hours")
        #expect(HistoryRange.tenDays.title == "10 Days")
    }
}

struct PmsetLogParserTests {
    @Test func parsesChargeLines() throws {
        let samples = PmsetLogParser.chargeSamples(Fixture.string("Battery/pmset-log-sample.txt"))
        #expect(samples.count == 31)
        let first = try #require(samples.first)
        let last = try #require(samples.last)
        #expect(first.percent == 77)
        #expect(!first.charging)
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-11-17T18:09:37+08:00"))
        #expect(last.percent == 44)
        #expect(samples.filter(\.charging).count == 19)
        #expect(samples.map(\.date) == samples.map(\.date).sorted())
    }

    @Test func emptyLog() {
        #expect(PmsetLogParser.chargeSamples("").isEmpty)
        #expect(PmsetLogParser.chargeSamples("Time stamp  Domain  Message\nnot a date (Charge: 50)\n").isEmpty)
    }

    @Test func bothChargeFormats() {
        let log = """
        2026-11-17 17:54:07 +0800 Assertions          \tSummary- [System: No Assertions] Using AC(Charge: 76)          
        2026-11-17 18:00:00 +0800 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:75%) 41 secs
        """
        #expect(PmsetLogParser.chargeSamples(log).map(\.percent) == [76, 75])
        #expect(PmsetLogParser.chargeSamples(log).map(\.charging) == [true, false])
    }
}
