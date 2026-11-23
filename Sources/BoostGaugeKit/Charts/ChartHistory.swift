import AppKit
import Foundation
import Observation

/// The shared time span every panel's chart shows. Raw values are stored, so never rename one.
public enum ChartRange: String, CaseIterable, Sendable {
    case tenMinutes = "10m", hour = "1h", day = "24h"

    public var title: String {
        switch self {
        case .tenMinutes: "10 Min"
        case .hour: "1 Hour"
        case .day: "24 Hours"
        }
    }

    public var span: TimeInterval {
        switch self {
        case .tenMinutes: 600
        case .hour: 3600
        case .day: 86_400
        }
    }

    /// The history tier that covers this range.
    var tier: Int {
        switch self {
        case .tenMinutes: 0
        case .hour: 1
        case .day: 2
        }
    }
}

/// Every series a chart draws. Raw values name the saved 24-hour tier, so never rename one.
public enum ChartSeriesID: String, CaseIterable, Sendable {
    case cpu = "cpu.usage"
    case gpu = "gpu.usage"
    case memoryUsed = "memory.used"
    case memoryPressure = "memory.pressure"
    case networkDown = "network.down"
    case networkUp = "network.up"
    case diskRead = "disk.read"
    case diskWrite = "disk.write"
    case tempsHottest = "temps.hottest"
    case tempsCPU = "temps.cpu"
    case tempsGPU = "temps.gpu"
    case powerSystem = "power.system"
    case powerBattery = "power.battery"
}

/// One chart point: a bucket's average and its highest reading. Times are seconds since the reference date.
public struct ChartPoint: Equatable, Sendable {
    public var t: TimeInterval
    public var avg: Float
    public var peak: Float

    public init(t: TimeInterval, avg: Float, peak: Float) {
        self.t = t
        self.avg = avg
        self.peak = peak
    }
}

/// A fixed ring of time buckets. Slot `b % capacity` holds bucket `b`; NaN marks a bucket nothing was recorded in,
/// which is how a gap (app not running, Mac asleep, item hidden) survives to the chart.
struct HistoryTier: Equatable {
    let bucket: TimeInterval
    let capacity: Int
    private(set) var avg: [Float]
    private(set) var peak: [Float]
    /// The newest bucket written.
    private(set) var head: Int?
    private var sum = 0.0
    private var count = 0

    init(bucket: TimeInterval, capacity: Int) {
        self.bucket = bucket
        self.capacity = capacity
        avg = Array(repeating: .nan, count: capacity)
        peak = Array(repeating: .nan, count: capacity)
    }

    static func == (a: HistoryTier, b: HistoryTier) -> Bool {
        a.bucket == b.bucket && a.capacity == b.capacity && a.head == b.head
            && a.avg.elementsEqual(b.avg) { $0 == $1 || ($0.isNaN && $1.isNaN) }
            && a.peak.elementsEqual(b.peak) { $0 == $1 || ($0.isNaN && $1.isNaN) }
    }

    func bucketNumber(_ t: TimeInterval) -> Int { Int((t / bucket).rounded(.down)) }

    private func slot(_ b: Int) -> Int { ((b % capacity) + capacity) % capacity }

    mutating func add(_ value: Float, at t: TimeInterval) {
        let b = bucketNumber(t)
        if let h = head {
            if b < h {
                // A small step back (clock nudged) is dropped; a big one would leave the ring unreadable, so restart.
                if h - b < capacity { return }
                self = HistoryTier(bucket: bucket, capacity: capacity)
                head = b
            } else if b > h {
                for i in 1...min(b - h, capacity) {
                    avg[slot(h + i)] = .nan
                    peak[slot(h + i)] = .nan
                }
                head = b
                sum = 0
                count = 0
            }
        } else {
            head = b
        }
        sum += Double(value)
        count += 1
        let i = slot(b)
        avg[i] = Float(sum / Double(count))
        peak[i] = peak[i].isNaN ? value : max(peak[i], value)
    }

    /// Recorded buckets from `start` to `end`, oldest first, each at its bucket's midpoint.
    func points(from start: TimeInterval, to end: TimeInterval) -> [ChartPoint] {
        guard let head else { return [] }
        let first = max(head - capacity + 1, bucketNumber(start))
        let last = min(head, bucketNumber(end))
        guard first <= last else { return [] }
        var out: [ChartPoint] = []
        out.reserveCapacity(last - first + 1)
        for b in first...last {
            let i = slot(b)
            guard !avg[i].isNaN else { continue }
            out.append(ChartPoint(t: min((Double(b) + 0.5) * bucket, end), avg: avg[i], peak: peak[i]))
        }
        return out
    }

    /// The saved form: the newest bucket and the whole ring.
    var saved: (head: Int, avg: [Float], peak: [Float])? { head.map { ($0, avg, peak) } }

    /// The stored running average resumes as one reading, so a relaunch inside the same minute doesn't zero it.
    mutating func restore(head: Int, avg: [Float], peak: [Float]) {
        guard avg.count == capacity, peak.count == capacity else { return }
        self.head = head
        self.avg = avg
        self.peak = peak
        let i = slot(head)
        sum = avg[i].isNaN ? 0 : Double(avg[i])
        count = avg[i].isNaN ? 0 : 1
    }
}

/// One series in three tiers: each reading, 5-second buckets for an hour, 1-minute buckets for a day.
/// About 20 KB, made on the first reading, so an item that's never shown costs nothing.
@MainActor @Observable public final class SeriesHistory {
    static let tierShapes: [(bucket: TimeInterval, capacity: Int)] = [(1, 600), (5, 720), (60, 1440)]
    /// A second reading this soon is the same moment read twice (Battery and Power share a beat, a preview ticks).
    static let minSpacing: TimeInterval = 0.5

    /// Bumped on every reading, so a chart on screen redraws.
    public private(set) var revision = 0
    @ObservationIgnored private(set) var tiers = tierShapes.map { HistoryTier(bucket: $0.bucket, capacity: $0.capacity) }
    @ObservationIgnored private var lastAt: TimeInterval?

    init() {}

    public func record(_ value: Double, at date: Date) {
        guard value.isFinite else { return }
        let t = date.timeIntervalSinceReferenceDate
        if let lastAt, abs(t - lastAt) < Self.minSpacing { return }
        lastAt = t
        for i in tiers.indices { tiers[i].add(Float(value), at: t) }
        revision &+= 1
    }

    /// The range's points ending at `now`, and the seconds between two of them before gaps. More than two per
    /// column are averaged down to one per column (the peak kept), so a day of minutes draws as about one point per
    /// pixel column, spaced a column apart.
    public func slice(_ range: ChartRange, now: Date,
                      columns: Int = ChartLayout.columns) -> (points: [ChartPoint], spacing: TimeInterval) {
        let end = now.timeIntervalSinceReferenceDate
        let tier = tiers[range.tier]
        let raw = tier.points(from: end - range.span, to: end)
        let thinned = raw.count > 2 * columns
        return (Self.thin(raw, from: end - range.span, to: end, columns: columns),
                thinned ? max(tier.bucket, range.span / Double(columns)) : tier.bucket)
    }

    public func points(_ range: ChartRange, now: Date, columns: Int = ChartLayout.columns) -> [ChartPoint] {
        slice(range, now: now, columns: columns).points
    }

    nonisolated static func thin(_ points: [ChartPoint], from start: TimeInterval, to end: TimeInterval,
                                 columns: Int) -> [ChartPoint] {
        guard points.count > 2 * columns, end > start, columns > 0 else { return points }
        let width = (end - start) / Double(columns)
        var out: [ChartPoint] = []
        out.reserveCapacity(columns)
        var column = -1, sumT = 0.0, sumAvg = 0.0, n = 0, peak = -Float.infinity
        func flush() {
            guard n > 0 else { return }
            out.append(ChartPoint(t: sumT / Double(n), avg: Float(sumAvg / Double(n)), peak: peak))
        }
        for p in points {
            let c = min(columns - 1, max(0, Int((p.t - start) / width)))
            if c != column {
                flush()
                column = c
                sumT = 0; sumAvg = 0; n = 0; peak = -.infinity
            }
            sumT += p.t
            sumAvg += Double(p.avg)
            peak = max(peak, p.peak)
            n += 1
        }
        flush()
        return out
    }
}

/// Every chart series, recorded from the item ticks. Only the 24-hour tier is saved: on quit, on sleep and every
/// ten minutes, so a relaunch or an update doesn't blank the day.
@MainActor public final class ChartHistory {
    private var series: [ChartSeriesID: SeriesHistory] = [:]
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private(set) var url: URL?

    public init() {}

    /// The series, made empty on first use.
    public func callAsFunction(_ id: ChartSeriesID) -> SeriesHistory {
        if let s = series[id] { return s }
        let s = SeriesHistory()
        series[id] = s
        return s
    }

    public func record(_ id: ChartSeriesID, _ value: Double?, at date: Date) {
        guard let value else { return }
        self(id).record(value, at: date)
    }

    var recordedSeries: Set<ChartSeriesID> { Set(series.keys) }

    // MARK: Saving

    public nonisolated static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("BoostGauge").appendingPathComponent("charts-24h.plist")
    }

    private struct Saved: Codable {
        struct Tier: Codable {
            var head: Int
            var avg: Data
            var peak: Data
        }
        var version = 1
        var bucket: TimeInterval
        var series: [String: Tier]
    }

    private static let dayTier = 2

    func encoded() throws -> Data {
        var out: [String: Saved.Tier] = [:]
        for (id, s) in series {
            guard let t = s.tiers[Self.dayTier].saved else { continue }
            out[id.rawValue] = Saved.Tier(head: t.head, avg: Self.data(t.avg), peak: Self.data(t.peak))
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(Saved(bucket: SeriesHistory.tierShapes[Self.dayTier].bucket, series: out))
    }

    /// Fills the 24-hour tier of every saved series. Anything unreadable is ignored: the day starts empty.
    func decode(_ data: Data) {
        guard let saved = try? PropertyListDecoder().decode(Saved.self, from: data), saved.version == 1,
              saved.bucket == SeriesHistory.tierShapes[Self.dayTier].bucket else { return }
        for (raw, tier) in saved.series {
            guard let id = ChartSeriesID(rawValue: raw) else { continue }
            let s = self(id)
            s.restoreDay(head: tier.head, avg: Self.floats(tier.avg), peak: Self.floats(tier.peak))
        }
    }

    private static func data(_ floats: [Float]) -> Data { floats.withUnsafeBufferPointer { Data(buffer: $0) } }

    private static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    public func load(from url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url) { decode(data) }
    }

    public func save() {
        guard let url, !series.isEmpty, let data = try? encoded() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Loads the saved day and saves it again every ten minutes and before sleep. The app calls `save()` on quit.
    public func startSaving(to url: URL = ChartHistory.defaultURL) {
        load(from: url)
        timer?.invalidate()
        let timer = Timer(timeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.save() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.save() }
        }
    }
}

extension SeriesHistory {
    func restoreDay(head: Int, avg: [Float], peak: [Float]) {
        tiers[2].restore(head: head, avg: avg, peak: peak)
        revision &+= 1
    }
}
