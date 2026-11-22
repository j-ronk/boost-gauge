import Foundation

extension PowerModeCommand {
    /// Always valid: the typed enums' raw values are exactly the range the raw initialiser accepts.
    init(source: PowerSource, mode: EnergyMode) {
        self = PowerModeCommand(rawSource: source.rawValue, rawMode: mode.rawValue)!
    }
}
