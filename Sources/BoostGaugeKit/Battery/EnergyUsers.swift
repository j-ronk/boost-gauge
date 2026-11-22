import Foundation

/// Per-app energy impact from `top`. It is Apple's unitless impact score, not watts.
enum EnergyUsers {
    typealias Row = (pid: pid_t, command: String, power: Double)

    /// `top -l 2` prints two samples; the first has no interval to measure over, so its power column is all zero.
    static func parseTop(_ out: String) -> [Row] {
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        let headers = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("PID") }
        guard headers.count >= 2, let header = headers.last else { return [] }
        var rows: [Row] = []
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = pid_t(parts[0]), let power = Double(parts[parts.count - 1]) else { continue }
            let command = parts[1..<(parts.count - 1)].joined(separator: " ")
            // Our own sampling run, which would otherwise rank near the top every time.
            if command == "top" { continue }
            rows.append((pid, command, power))
        }
        return rows
    }

    static func rollup(_ rows: [Row], identify: (pid_t) -> (key: String, name: String)) -> [(key: String, name: String, power: Double)] {
        var totals: [String: (name: String, power: Double)] = [:]
        var order: [String] = []
        for row in rows where row.power > 0 {
            let who = identify(row.pid)
            if totals[who.key] == nil {
                totals[who.key] = (who.name, 0)
                order.append(who.key)
            }
            totals[who.key]!.power += row.power
        }
        let sorted = order.compactMap { key in totals[key].map { (key: key, name: $0.name, power: $0.power) } }
            .enumerated()
            .sorted { $0.element.power != $1.element.power ? $0.element.power > $1.element.power : $0.offset < $1.offset }
            .map(\.element)
        return Array(sorted.prefix(5))
    }
}
