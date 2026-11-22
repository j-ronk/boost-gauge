import Foundation

public enum Format {
    public static func percent(_ v: Double) -> String {
        let r = v.rounded()
        // Int(_:) traps outside its range; garbage readings must not crash the menu bar.
        guard r.isFinite, abs(r) < 1e15 else { return "—" }
        return "\(Int(r))%"
    }

    public static func watts(_ w: Double) -> String {
        guard w.isFinite else { return "—" }
        // Adding 0 turns a rounded -0.0 into 0.0, so tiny negative noise never prints "-0.0 W".
        return String(format: "%.1f W", (w * 10).rounded() / 10 + 0)
    }

    /// Positive is charging, negative draining. Uses U+2212 so the sign is as wide as "+".
    public static func signedWatts(_ w: Double) -> String {
        guard w.isFinite else { return "—" }
        let rounded = (w * 10).rounded() / 10
        if rounded == 0 { return "0.0 W" }
        return String(format: "%@%.1f W", rounded > 0 ? "+" : "\u{2212}", abs(rounded))
    }

    public static func hm(minutes: Int) -> String {
        let m = max(0, minutes)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
