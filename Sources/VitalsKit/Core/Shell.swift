import Foundation

public enum Shell {
    /// Runs a tool off the main actor and returns its exit status and stdout. Status -1 means it couldn't start.
    public static func run(_ path: String, _ args: [String]) async -> (status: Int32, out: String) {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            // An unread stderr pipe can fill and block the child forever.
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return (Int32(-1), "") }
            // Drain before waiting: a full stdout pipe would otherwise deadlock against waitUntilExit.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
