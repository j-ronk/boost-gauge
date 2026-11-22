import Foundation

struct ChargeSample: Equatable, Sendable {
    var date: Date
    var percent: Int
    var charging: Bool
}

enum HistoryRange: Hashable, CaseIterable, Sendable {
    case day, tenDays

    var title: String {
        switch self {
        case .day: "24 Hours"
        case .tenDays: "10 Days"
        }
    }

    var span: TimeInterval {
        switch self {
        case .day: 86_400
        case .tenDays: 10 * 86_400
        }
    }

    var bucket: TimeInterval {
        switch self {
        case .day: 300
        case .tenDays: 1_800
        }
    }

    /// Longer than this between points means the Mac slept or Boost Gauge wasn't running: break the line there.
    /// Generous because first-launch history seeded from `pmset -g log` has a point only every 10–60 minutes.
    var gap: TimeInterval {
        switch self {
        case .day: 5_400
        case .tenDays: 9_000
        }
    }
}

/// Battery charge history as an append-only CSV ("epochSeconds,percent,charging"), one line a minute, kept 10 days.
/// Plain text so a bad write costs one line, not the file.
final class HistoryStore {
    static let keep: TimeInterval = 10 * 86_400

    let url: URL
    private(set) var samples: [ChargeSample]

    init(url: URL) {
        self.url = url
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        samples = text.split(separator: "\n").compactMap(Self.parse).sorted { $0.date < $1.date }
    }

    static let fileName = "battery-history.csv"

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("BoostGauge").appendingPathComponent(fileName)
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func append(_ sample: ChargeSample) {
        if let last = samples.last, sample.date < last.date {
            samples.append(sample)
            samples.sort { $0.date < $1.date }
        } else {
            samples.append(sample)
        }
        appendToFile(Self.line(sample) + "\n")
    }

    /// First-launch backfill from `pmset -g log`: merged in date order, then the file is rewritten once.
    func seed(_ older: [ChargeSample]) {
        guard !older.isEmpty else { return }
        samples = (older + samples).sorted { $0.date < $1.date }
        rewrite()
    }

    func compact(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.keep)
        guard samples.contains(where: { $0.date < cutoff }) else { return }
        samples.removeAll { $0.date < cutoff }
        rewrite()
    }

    /// Last sample per bucket, split into segments wherever the gap is too long to draw a line across.
    func series(_ range: HistoryRange, now: Date) -> [[ChargeSample]] {
        Self.series(of: samples, range, now: now)
    }

    static func series(of samples: [ChargeSample], _ range: HistoryRange, now: Date) -> [[ChargeSample]] {
        let start = now.addingTimeInterval(-range.span)
        var bucketed: [ChargeSample] = []
        var lastBucket: Int?
        for sample in samples where sample.date >= start && sample.date <= now {
            let bucket = Int((sample.date.timeIntervalSince1970 / range.bucket).rounded(.down))
            if bucket == lastBucket {
                bucketed[bucketed.count - 1] = sample
            } else {
                bucketed.append(sample)
                lastBucket = bucket
            }
        }
        var segments: [[ChargeSample]] = []
        for sample in bucketed {
            if let previous = segments.last?.last, sample.date.timeIntervalSince(previous.date) <= range.gap {
                segments[segments.count - 1].append(sample)
            } else {
                segments.append([sample])
            }
        }
        return segments
    }

    private static func line(_ s: ChargeSample) -> String {
        "\(Int(s.date.timeIntervalSince1970)),\(s.percent),\(s.charging ? 1 : 0)"
    }

    private static func parse(_ line: Substring) -> ChargeSample? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 3, let epoch = Int(fields[0]), let percent = Int(fields[1]), (0...100).contains(percent),
              let flag = Int(fields[2]), flag == 0 || flag == 1 else { return nil }
        return ChargeSample(date: Date(timeIntervalSince1970: TimeInterval(epoch)), percent: percent, charging: flag == 1)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func appendToFile(_ text: String) {
        ensureDirectory()
        guard let handle = try? FileHandle(forUpdating: url) else {
            try? Data(text.utf8).write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        // A write cut off mid-line (crash, full disk) would otherwise glue the next sample onto it.
        var prefix = ""
        if let end = try? handle.seekToEnd(), end > 0 {
            try? handle.seek(toOffset: end - 1)
            if handle.readData(ofLength: 1) != Data("\n".utf8) { prefix = "\n" }
            _ = try? handle.seekToEnd()
        }
        try? handle.write(contentsOf: Data((prefix + text).utf8))
    }

    private func rewrite() {
        ensureDirectory()
        let text = samples.map { Self.line($0) + "\n" }.joined()
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}
