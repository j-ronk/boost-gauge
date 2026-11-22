import Foundation

/// Reads each source's `powermode` from `pmset -g custom`, which needs no root.
enum PmsetCustomParser {
    static func modes(_ out: String) -> [PowerSource: EnergyMode] {
        var modes: [PowerSource: EnergyMode] = [:]
        var block: PowerSource?
        for line in out.split(whereSeparator: \.isNewline) {
            // Block headers sit at column 0; settings are indented beneath them.
            if let first = line.first, !first.isWhitespace {
                switch line.trimmingCharacters(in: .whitespaces) {
                case "Battery Power:": block = .battery
                case "AC Power:": block = .adapter
                default: block = nil
                }
                continue
            }
            guard let source = block else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count == 2, parts[0] == "powermode", let raw = Int(parts[1]), let mode = EnergyMode(rawValue: raw) {
                modes[source] = mode
            }
        }
        return modes
    }
}
