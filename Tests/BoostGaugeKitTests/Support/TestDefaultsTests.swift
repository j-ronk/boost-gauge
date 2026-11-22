import Foundation
import Testing

struct TestDefaultsTests {
    @Test func removingASuiteDeletesItsPlist() {
        let suite = TestDefaults()
        suite.defaults.set(true, forKey: "written")
        suite.defaults.synchronize()
        #expect(FileManager.default.fileExists(atPath: suite.plistURL.path))

        TestDefaults.remove(suite.name)

        #expect(!FileManager.default.fileExists(atPath: suite.plistURL.path))
        #expect(suite.reopen().object(forKey: "written") == nil)
    }
}
