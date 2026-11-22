import Foundation
import Testing
@testable import BoostGaugeKit

struct AppIdentityTests {
    @Test func chromeHelperRollsUpToOutermostApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppIdentity.outermostAppPath(executablePath: path) == "/Applications/Google Chrome.app")
    }

    @Test func bareToolHasNoApp() {
        #expect(AppIdentity.outermostAppPath(executablePath: "/usr/local/bin/node") == nil)
        #expect(AppIdentity.outermostAppPath(executablePath: "") == nil)
    }

    @Test @MainActor func resolvesOwnProcess() {
        let me = AppIdentity.resolve(pid: ProcessInfo.processInfo.processIdentifier)
        #expect(!me.key.isEmpty)
        #expect(!me.name.isEmpty)
    }

    // Recorded fixtures from a live machine, not live pids.
    static let claudePath = "/Users/someone/.local/share/claude/versions/2.1.327"
    static let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.EnhancedSecurity.xpc/Contents/MacOS/com.apple.WebKit.WebContent.EnhancedSecurity"

    @Test func versionedExecutableShowsToolName() {
        #expect(AppIdentity.displayName(processName: "2.1.327", executablePath: Self.claudePath) == "Claude Code")
        #expect(AppIdentity.displayName(processName: "1.4.0", executablePath: "/opt/mytool/versions/1.4.0") == "mytool")
        #expect(AppIdentity.displayName(processName: "3.2.1", executablePath: "/usr/local/Cellar/ripgrep/3.2.1/bin/3.2.1") == "ripgrep")
    }

    @Test func versionRuleIsConservative() {
        #expect(AppIdentity.looksLikeVersion("2.1.327"))
        #expect(!AppIdentity.looksLikeVersion("python3.12"))
        #expect(!AppIdentity.looksLikeVersion("7zip"))
        #expect(!AppIdentity.looksLikeVersion("node"))
        #expect(AppIdentity.displayName(processName: "node", executablePath: "/usr/local/bin/node") == "node")
        // No meaningful directory: keep what we have.
        #expect(AppIdentity.displayName(processName: "1.0.0", executablePath: "/bin/1.0.0") == "1.0.0")
    }

    @Test func webKitHelpersAreSystemHelpersWithNoOwnApp() {
        #expect(AppIdentity.isSystemHelper(executablePath: Self.webContent))
        #expect(AppIdentity.outermostAppPath(executablePath: Self.webContent) == nil)
        #expect(!AppIdentity.isSystemHelper(executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"))
        #expect(!AppIdentity.isSystemHelper(executablePath: "/usr/local/bin/node"))
        #expect(!AppIdentity.isSystemHelper(executablePath: ""))
    }

    @Test func fallbackIconIsNeverBlank() {
        #expect(AppIdentity.fallbackIconType(executablePath: Self.webContent) == .applicationBundle)
        #expect(AppIdentity.fallbackIconType(executablePath: Self.claudePath) == .unixExecutable)
        #expect(AppIdentity.fallbackIconType(executablePath: "") == .unixExecutable)
    }

    @Test func versionNameFallbackSkipsHomeAndTmp() {
        #expect(AppIdentity.displayName(processName: "2.0.1", executablePath: "/tmp/2.0.1") == "2.0.1")
    }
}
