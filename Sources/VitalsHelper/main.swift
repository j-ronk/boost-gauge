import Foundation

// Without a stamped identity there is no caller requirement to enforce, so don't serve at all.
guard let identity = HelperIdentity.current, Bundle.main.bundleIdentifier == identity.helperBundleID else {
    FileHandle.standardError.write(Data("VitalsHelper: no valid identity in Info.plist\n".utf8))
    exit(1)
}

/// Runs as root under launchd, started on demand when Vitals connects to the Mach service.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let callerRequirement: String

    init(callerRequirement: String) {
        self.callerRequirement = callerRequirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from any peer that fails this are dropped and the connection invalidated.
        connection.setCodeSigningRequirement(callerRequirement)
        connection.exportedInterface = NSXPCInterface(with: VitalsHelperProtocol.self)
        connection.exportedObject = HelperService(run: HelperService.runProcess)
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate(callerRequirement: identity.callerRequirement)
let listener = NSXPCListener(machServiceName: identity.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
