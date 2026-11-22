import Foundation

private final class FixtureBundleToken {}

/// Fixtures ship as a folder reference, so paths keep their subfolders: `Fixture.string("Core/hello.txt")`.
enum Fixture {
    static func url(_ path: String) -> URL {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let root = bundle.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures folder missing from \(bundle.bundlePath)")
        }
        return root.appendingPathComponent(path)
    }

    static func data(_ path: String) -> Data {
        do { return try Data(contentsOf: url(path)) } catch { fatalError("Fixture \(path): \(error)") }
    }

    static func string(_ path: String) -> String {
        String(decoding: data(path), as: UTF8.self)
    }

    /// `ioreg -a` output is a top-level array of services; callers unwrap whichever shape they recorded.
    static func plist(_ path: String) -> Any {
        do { return try PropertyListSerialization.propertyList(from: data(path), format: nil) } catch {
            fatalError("Fixture \(path) is not a plist: \(error)")
        }
    }
}
