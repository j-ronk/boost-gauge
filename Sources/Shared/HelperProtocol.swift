import Foundation

// Compiled into both BoostGaugeKit and BoostGaugeHelper so both ends of the XPC connection agree.

/// The helper's whole surface. Plain integers cross the wire and the helper re-validates them,
/// so a caller can't name a flag, path or command.
@objc public protocol BoostGaugeHelperProtocol {
    func setPowerMode(source: Int, mode: Int, reply: @escaping (Bool) -> Void)
}

/// Who the app and the helper are, read from the signed Info.plist so a fork can change its team and bundle
/// prefix in Config/Signing.xcconfig without touching code.
public struct HelperIdentity: Equatable, Sendable {
    public static let appBundleIDKey = "BoostGaugeAppBundleIdentifier"
    public static let teamIDKey = "BoostGaugeTeamIdentifier"

    /// This process's identity, or nil if the build didn't stamp one; callers then refuse to connect.
    public static let current = HelperIdentity(infoDictionary: Bundle.main.infoDictionary)

    public let appBundleID: String
    public let teamID: String

    /// Both values are spliced into requirement strings, so only plain bundle IDs and team IDs get through.
    public init?(appBundleID: String, teamID: String) {
        guard appBundleID.wholeMatch(of: #/[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*/#) != nil,
              teamID.wholeMatch(of: #/[A-Z0-9]{10}/#) != nil
        else { return nil }
        self.appBundleID = appBundleID
        self.teamID = teamID
    }

    public init?(infoDictionary: [String: Any]?) {
        guard let app = infoDictionary?[Self.appBundleIDKey] as? String,
              let team = infoDictionary?[Self.teamIDKey] as? String
        else { return nil }
        self.init(appBundleID: app, teamID: team)
    }

    public var helperBundleID: String { appBundleID + ".Helper" }
    public var machServiceName: String { helperBundleID }
    public var plistName: String { helperBundleID + ".plist" }

    /// The helper runs as root, so it only talks to Boost Gauge signed by the same team.
    public var callerRequirement: String { requirement(appBundleID) }
    /// The app checks the other way too, so a look-alike service can't fake success.
    public var helperRequirement: String { requirement(helperBundleID) }

    private func requirement(_ identifier: String) -> String {
        #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(teamID)""#
    }
}
