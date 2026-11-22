import Foundation

/// One validated `pmset` invocation. Only these six commands can exist, and none of them is `-a`,
/// which would overwrite both power sources at once.
public struct PowerModeCommand: Equatable, Sendable {
    public static let executable = "/usr/bin/pmset"

    public let rawSource: Int
    public let rawMode: Int

    /// Source 0 is battery (`-b`) and 1 is adapter (`-c`); modes are pmset's 0 automatic, 1 low, 2 high.
    public init?(rawSource: Int, rawMode: Int) {
        guard (0...1).contains(rawSource), (0...2).contains(rawMode) else { return nil }
        self.rawSource = rawSource
        self.rawMode = rawMode
    }

    public var arguments: [String] {
        [rawSource == 0 ? "-b" : "-c", "powermode", String(rawMode)]
    }
}
