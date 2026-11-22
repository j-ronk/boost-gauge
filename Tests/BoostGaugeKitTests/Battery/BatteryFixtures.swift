import Foundation
@testable import BoostGaugeKit

/// Recorded states have plain names; `-synth` files are hand-edited copies of the recorded draining-on-ac pair
/// for states this Mac couldn't be put in while recording.
enum BatteryFixtures {
    static func iops(_ state: String) -> [String: Any] {
        Fixture.plist("Battery/iops-\(state).plist") as! [String: Any]
    }

    static func smartBattery(_ state: String) -> [String: Any] {
        (Fixture.plist("Battery/smartbattery-\(state).plist") as! [[String: Any]])[0]
    }

    static var pack: [String: Any] {
        (Fixture.plist("Battery/pack.plist") as! [[String: Any]])[0]
    }

    static func snapshot(_ state: String, withPack: Bool = false) -> BatterySnapshot {
        BatteryParser.parse(iops: iops(state), smartBattery: smartBattery(state), pack: withPack ? pack : nil)
    }
}
