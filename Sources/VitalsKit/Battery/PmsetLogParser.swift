import Foundation

enum PmsetLogParser {
    static func chargeSamples(_ log: String) -> [ChargeSample] {
        // "2026-11-17 17:54:07 +0800 ... Using AC(Charge: 76)" and "... Using Batt (Charge:75%) 41 secs"
        let chargePattern = #/Using (AC|Batt|BATT) ?\(Charge: ?(\d{1,3})/#
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var result: [ChargeSample] = []
        for line in log.split(separator: "\n") where line.count > 25 {
            guard let match = line.firstMatch(of: chargePattern), let percent = Int(match.2), percent <= 100,
                  let date = formatter.date(from: String(line.prefix(25))) else { continue }
            // pmset logs the power source, not charge direction; on AC is the closest it gets to "charging".
            result.append(ChargeSample(date: date, percent: percent, charging: match.1 == "AC"))
        }
        return result.sorted { $0.date < $1.date }
    }
}
