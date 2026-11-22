import AppKit
import Darwin
import UniformTypeIdentifiers

public enum AppIdentity {
    /// Helpers (Chrome renderers, WebKit content) live inside their parent app, so the outermost
    /// `.app` is the one a person recognises, the same rollup Apple's battery menu does.
    public static func outermostAppPath(executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else {
            return executablePath.hasSuffix(".app") ? executablePath : nil
        }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }

    /// A bare version number ("2.1.327") is a versioned executable, never a name worth showing.
    public static func looksLikeVersion(_ name: String) -> Bool {
        !name.isEmpty && name.first!.isNumber && name.allSatisfy { $0.isNumber || $0 == "." } && name.contains(".")
    }

    private static let containerDirs: Set<String> = ["versions", "version", "bin", "lib", "libexec", "current", "releases", "release", "latest", "share", "local", "macos", "users", "home", "tmp", "opt", "usr", "var", "private", "cellar"]
    private static let knownNames = ["claude": "Claude Code"]

    /// The meaningful directory name above a versioned executable, e.g. `.../claude/versions/2.1.327` gives "claude".
    public static func versionedToolName(executablePath: String) -> String? {
        let parts = executablePath.split(separator: "/").dropLast().map(String.init)
        guard let dir = parts.last(where: { !containerDirs.contains($0.lowercased()) && !$0.hasPrefix(".") && !looksLikeVersion($0) }) else { return nil }
        return knownNames[dir.lowercased()] ?? dir
    }

    /// Name to show for a process: bare version numbers are replaced by the tool's directory name.
    public static func displayName(processName: String, executablePath: String) -> String {
        guard looksLikeVersion(processName) else { return processName }
        return versionedToolName(executablePath: executablePath) ?? processName
    }

    /// System helpers (WebKit XPC services and the like) have no `.app` of their own.
    public static func isSystemHelper(executablePath: String) -> Bool {
        !executablePath.isEmpty && outermostAppPath(executablePath: executablePath) == nil
            && (executablePath.hasPrefix("/System/Library/") || executablePath.hasPrefix("/usr/libexec/") || executablePath.contains(".xpc/"))
    }

    /// The app a process belongs to: its own bundle, else, for system helpers, the app responsible for it.
    public static func owningAppPath(pid: pid_t, executablePath: String) -> String? {
        if let own = outermostAppPath(executablePath: executablePath) { return own }
        guard isSystemHelper(executablePath: executablePath), let owner = responsiblePid(for: pid), owner != pid else { return nil }
        return outermostAppPath(executablePath: Self.executablePath(pid: owner))
    }

    public static func resolve(pid: pid_t) -> (key: String, name: String, icon: NSImage) {
        let path = executablePath(pid: pid)
        let procName = processName(pid: pid) ?? (path as NSString).lastPathComponent
        if let bundlePath = owningAppPath(pid: pid, executablePath: path) {
            let name = (FileManager.default.displayName(atPath: bundlePath) as NSString).deletingPathExtension
            return (bundlePath, name, NSWorkspace.shared.icon(forFile: bundlePath))
        }
        if looksLikeVersion(procName) {
            let name = displayName(processName: procName, executablePath: path)
            return ("cmd:" + name, name, NSWorkspace.shared.icon(for: .unixExecutable))
        }
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return (name, name, app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
        }
        // icon(forFile:) gives a blank document for bare binaries, so use the terminal-program icon instead.
        let icon = NSWorkspace.shared.icon(for: fallbackIconType(executablePath: path))
        return ("cmd:" + procName, procName.isEmpty ? "pid \(pid)" : procName, icon)
    }

    public static func fallbackIconType(executablePath: String) -> UTType {
        isSystemHelper(executablePath: executablePath) ? .applicationBundle : .unixExecutable
    }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static func responsiblePid(for pid: pid_t) -> pid_t? {
        guard let fn = responsibleFn else { return nil }
        let owner = fn(pid)
        return owner > 0 ? owner : nil
    }

    private static func executablePath(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }

    private static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}
