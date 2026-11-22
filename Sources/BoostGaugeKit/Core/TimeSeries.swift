import Foundation

/// In-memory chart buffer fed from the menu bar tick, so a chart never opens empty.
public struct TimeSeries {
    public let window: TimeInterval
    private var samples: [(date: Date, value: Double)] = []

    public init(window: TimeInterval = 600) {
        self.window = window
    }

    public mutating func append(_ value: Double, at date: Date) {
        samples.append((date, value))
        let cutoff = date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    public var points: [(date: Date, value: Double)] { samples }
}
