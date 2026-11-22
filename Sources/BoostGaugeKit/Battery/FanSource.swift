import Foundation

/// Opens the SMC on the first read, so a Mac with the panel never opened never touches it.
final class FanSource: @unchecked Sendable {
    private var smc: SMC?
    func read() -> [FanReading] {
        if smc == nil { smc = SMC() }
        return smc?.fans() ?? []
    }
}
