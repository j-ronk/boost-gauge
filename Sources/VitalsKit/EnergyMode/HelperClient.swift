import Foundation
import os
import ServiceManagement

@MainActor protocol HelperClient {
    func setPowerMode(_ command: PowerModeCommand) async -> Bool
}

/// The SMAppService daemon registration, behind a seam so the approval flow is testable without touching launchd.
@MainActor protocol DaemonService {
    var status: HelperStatus { get }
    func register() throws
    func openLoginItems()
}

@MainActor protocol ModeReader {
    func read() async -> [PowerSource: EnergyMode]
}

extension HelperStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }
}

let energyModeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vitals", category: "EnergyMode")

/// Thrown when the app's Info.plist carries no usable identity, so there is no helper to name.
struct MissingHelperIdentity: Error {}

final class XPCHelperClient: HelperClient {
    private let identity = HelperIdentity.current

    func setPowerMode(_ command: PowerModeCommand) async -> Bool {
        guard let identity else {
            energyModeLog.error("no helper identity in Info.plist")
            return false
        }
        let connection = NSXPCConnection(machServiceName: identity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: VitalsHelperProtocol.self)
        connection.setCodeSigningRequirement(identity.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { continuation in
            let reply = ReplyOnce(continuation)
            // Longer than the helper's own pmset watchdog, so a hung call still ends and frees the picker.
            Task {
                try? await Task.sleep(for: .seconds(8))
                reply.resume(false)
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                energyModeLog.error("helper unreachable: \(error.localizedDescription, privacy: .public)")
                reply.resume(false)
            }
            guard let helper = proxy as? VitalsHelperProtocol else {
                reply.resume(false)
                return
            }
            helper.setPowerMode(source: command.rawSource, mode: command.rawMode) { reply.resume($0) }
        }
    }
}

/// XPC promises the reply or the error handler, but a checked continuation must never resume twice, so guard anyway.
private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

final class SMDaemonService: DaemonService {
    private let service = HelperIdentity.current.map { SMAppService.daemon(plistName: $0.plistName) }

    var status: HelperStatus { service.map { HelperStatus($0.status) } ?? .unavailable }

    func register() throws {
        guard let service else { throw MissingHelperIdentity() }
        try service.register()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct PmsetModeReader: ModeReader {
    func read() async -> [PowerSource: EnergyMode] {
        let (status, out) = await Shell.run(PowerModeCommand.executable, ["-g", "custom"])
        guard status == 0 else { return [:] }
        return PmsetCustomParser.modes(out)
    }
}
