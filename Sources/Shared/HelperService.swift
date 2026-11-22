import Foundation

/// The helper's exported object. Lives in Shared so the validation is unit-tested from BoostGaugeKitTests.
public final class HelperService: NSObject, BoostGaugeHelperProtocol {
    public typealias Runner = (_ path: String, _ arguments: [String]) -> Int32

    private let run: Runner

    public init(run: @escaping Runner) {
        self.run = run
    }

    public func setPowerMode(source: Int, mode: Int, reply: @escaping (Bool) -> Void) {
        guard let command = PowerModeCommand(rawSource: source, rawMode: mode) else {
            reply(false)
            return
        }
        reply(run(PowerModeCommand.executable, command.arguments) == 0)
    }

    /// Exit status of the tool, or -1 if it couldn't start.
    public static func runProcess(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        // pmset returns in milliseconds; a hang would otherwise block this XPC connection for good.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
