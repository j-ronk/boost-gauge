import Foundation
import Security
import Testing
@testable import VitalsKit

/// The helper's request handling lives in Shared so it can be tested here; main.swift only wires it to XPC.
struct HelperServiceTests {
    final class Runner: @unchecked Sendable {
        var runs: [(String, [String])] = []
        var exitCode: Int32 = 0
        func run(_ path: String, _ args: [String]) -> Int32 {
            runs.append((path, args))
            return exitCode
        }
    }

    private func call(_ service: HelperService, _ source: Int, _ mode: Int) -> Bool? {
        var reply: Bool?
        service.setPowerMode(source: source, mode: mode) { reply = $0 }
        return reply
    }

    @Test func validRunsPmsetForThatSource() {
        let runner = Runner()
        let service = HelperService(run: runner.run)
        #expect(call(service, 0, 1) == true)
        #expect(call(service, 1, 2) == true)
        #expect(runner.runs.map(\.0) == ["/usr/bin/pmset", "/usr/bin/pmset"])
        #expect(runner.runs.map(\.1) == [["-b", "powermode", "1"], ["-c", "powermode", "2"]])
    }

    @Test(arguments: [(2, 0), (0, 3), (0, -1), (-1, -1), (99, 1)])
    func invalidRepliesFalseAndRunsNothing(source: Int, mode: Int) {
        let runner = Runner()
        #expect(call(HelperService(run: runner.run), source, mode) == false)
        #expect(runner.runs.isEmpty)
    }

    @Test func nonzeroExitRepliesFalse() {
        let runner = Runner()
        runner.exitCode = 1
        #expect(call(HelperService(run: runner.run), 0, 0) == false)
        #expect(runner.runs.count == 1)
    }

    @Test func launchFailureRepliesFalse() {
        let runner = Runner()
        runner.exitCode = -1
        #expect(call(HelperService(run: runner.run), 1, 0) == false)
    }
}

struct HelperIdentityTests {
    private let example = HelperIdentity(appBundleID: "com.example.Vitals", teamID: "ABCDE12345")!
    private let other = HelperIdentity(appBundleID: "org.sample.Vitals", teamID: "XYZ9876543")!

    @Test func requirementsCompile() {
        for identity in [example, other] {
            for text in [identity.callerRequirement, identity.helperRequirement] {
                var requirement: SecRequirement?
                #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, "\(text)")
                #expect(requirement != nil)
            }
        }
    }

    /// The requirement pins both the exact bundle ID and the team, nothing looser.
    @Test func callerIsVitalsOnTeam() {
        #expect(example.callerRequirement
            == #"anchor apple generic and identifier "com.example.Vitals" and certificate leaf[subject.OU] = "ABCDE12345""#)
        #expect(example.helperRequirement
            == #"anchor apple generic and identifier "com.example.Vitals.Helper" and certificate leaf[subject.OU] = "ABCDE12345""#)
        #expect(example.helperBundleID == "com.example.Vitals.Helper")
        #expect(example.machServiceName == "com.example.Vitals.Helper")
        #expect(example.plistName == "com.example.Vitals.Helper.plist")
    }

    @Test func otherPrefixAndTeamPinThemInstead() {
        #expect(other.callerRequirement
            == #"anchor apple generic and identifier "org.sample.Vitals" and certificate leaf[subject.OU] = "XYZ9876543""#)
        #expect(other.helperRequirement
            == #"anchor apple generic and identifier "org.sample.Vitals.Helper" and certificate leaf[subject.OU] = "XYZ9876543""#)
        #expect(other.machServiceName == "org.sample.Vitals.Helper")
        #expect(other.plistName == "org.sample.Vitals.Helper.plist")
    }

    /// The values end up inside a requirement string, so anything that could change its meaning is refused.
    @Test(arguments: [
        ("", "ABCDE12345"),
        ("com.example.Vitals", ""),
        ("com.example.Vitals", "abcde12345"),
        ("com.example.Vitals", "ABCDE1234"),
        ("com.example.Vitals", "ABCDE12345X"),
        ("com.example.Vitals", #"ABCDE12345" or anchor apple"#),
        (#"com.example.Vitals" or identifier "x"#, "ABCDE12345"),
        ("com.example Vitals", "ABCDE12345"),
        (".Vitals", "ABCDE12345"),
        ("com.example.Vitals.", "ABCDE12345"),
        ("au..Vitals", "ABCDE12345"),
        ("$(VITALS_APP_BUNDLE_ID)", "ABCDE12345"),
    ])
    func rejectsUnsafeValues(app: String, team: String) {
        #expect(HelperIdentity(appBundleID: app, teamID: team) == nil)
    }

    @Test func readsTheBuiltInfoPlist() {
        let info: [String: Any] = [
            HelperIdentity.appBundleIDKey: "com.example.Vitals",
            HelperIdentity.teamIDKey: "ABCDE12345",
        ]
        #expect(HelperIdentity(infoDictionary: info) == example)
    }

    /// No identity means no requirement, so the helper and the app refuse to talk rather than trust anyone.
    @Test func missingOrBadInfoPlistValuesGiveNoIdentity() {
        #expect(HelperIdentity(infoDictionary: nil) == nil)
        #expect(HelperIdentity(infoDictionary: [:]) == nil)
        #expect(HelperIdentity(infoDictionary: [HelperIdentity.appBundleIDKey: "com.example.Vitals"]) == nil)
        #expect(HelperIdentity(infoDictionary: [HelperIdentity.teamIDKey: "ABCDE12345"]) == nil)
        #expect(HelperIdentity(infoDictionary: [
            HelperIdentity.appBundleIDKey: "com.example.Vitals",
            HelperIdentity.teamIDKey: 42,
        ]) == nil)
        #expect(HelperIdentity(infoDictionary: [
            HelperIdentity.appBundleIDKey: "$(VITALS_APP_BUNDLE_ID)",
            HelperIdentity.teamIDKey: "$(DEVELOPMENT_TEAM)",
        ]) == nil)
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The build fills the launchd plist template with the app's bundle ID; check the result agrees with the code.
    @Test(arguments: ["com.example.Vitals", "org.sample.Vitals"])
    func launchdPlistMatches(app: String) throws {
        let identity = try #require(HelperIdentity(appBundleID: app, teamID: "ABCDE12345"))
        let template = try String(contentsOf: root.appendingPathComponent("Sources/VitalsHelper/Helper.launchd.plist"), encoding: .utf8)
        let filled = template.replacingOccurrences(of: "${VITALS_APP_BUNDLE_ID}", with: app)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(filled.utf8), format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == identity.machServiceName)
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/VitalsHelper")
        #expect((plist["MachServices"] as? [String: Bool])?[identity.machServiceName] == true)
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [app])
        #expect(plist["Program"] == nil)
        #expect(plist["ProgramArguments"] == nil)
    }

    /// The build script names the installed plist after the helper, which is what SMAppService is asked for.
    @Test func buildScriptNamesPlistLikeTheCode() throws {
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(yml.contains("Library/LaunchDaemons/${VITALS_APP_BUNDLE_ID}.Helper.plist"))
        #expect(example.plistName == "\(example.appBundleID).Helper.plist")
    }
}
