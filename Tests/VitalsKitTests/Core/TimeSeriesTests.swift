import Foundation
import Testing
@testable import VitalsKit

struct TimeSeriesTests {
    private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_000_000 + s) }

    @Test func dropsOlderThanWindow() {
        var series = TimeSeries(window: 600)
        series.append(10, at: at(0))
        series.append(20, at: at(300))
        series.append(30, at: at(601))
        #expect(series.points.map(\.date) == [at(300), at(601)])
        #expect(series.points.map(\.value) == [20, 30])
    }

    @Test func defaultWindowIsTenMinutes() {
        var series = TimeSeries()
        series.append(1, at: at(0))
        series.append(2, at: at(600))
        #expect(series.points.count == 2)
        series.append(3, at: at(601))
        #expect(series.points.map(\.value) == [2, 3])
    }

    @Test func emptyHasNoPoints() {
        #expect(TimeSeries().points.isEmpty)
    }
}
