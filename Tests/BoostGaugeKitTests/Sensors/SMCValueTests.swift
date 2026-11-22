import Foundation
import Testing
@testable import BoostGaugeKit

struct SMCValueTests {
    @Test func flt() {
        let bytes = withUnsafeBytes(of: Float(2317.0).bitPattern.littleEndian, Array.init)
        #expect(SMCValue.decode(type: "flt ", bytes: bytes) == 2317.0)
    }

    @Test func fpe2() {
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x24, 0x34]) == 2317.0)
    }

    @Test func unsignedInts() {
        #expect(SMCValue.decode(type: "ui8 ", bytes: [0x02]) == 2)
        #expect(SMCValue.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCValue.decode(type: "ui32", bytes: [0, 0, 0x08, 0xCD]) == 2253)
    }

    /// The kernel reads this struct by layout; Stats' SMCKeyData_t is 80 bytes with the value bytes at 48.
    @Test func keyDataLayout() {
        #expect(MemoryLayout<SMCKeyData>.stride == 80)
        #expect(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.bytes) == 48)
        #expect(MemoryLayout<SMCKeyData>.offset(of: \SMCKeyData.keyInfo) == 28)
    }

    @Test func unknownTypeNil() {
        #expect(SMCValue.decode(type: "sp78", bytes: [0x40, 0x00]) == nil)
        #expect(SMCValue.decode(type: "{fds", bytes: Array(repeating: 0x41, count: 16)) == nil)
    }

    @Test func shortBytesNil() {
        #expect(SMCValue.decode(type: "flt ", bytes: [0x00, 0x00]) == nil)
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x24]) == nil)
        #expect(SMCValue.decode(type: "ui8 ", bytes: []) == nil)
    }

    /// The borrowed SMC code is where a write could creep in, so the source itself is checked.
    @Test func sensorsSourceHasNoSMCWrite() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../Sources/BoostGaugeKit/Sensors").standardizedFileURL
        let files = try #require(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for marker in ["kSMCWriteKey", "writeKey", "writeBytes", "IOConnectCallScalarMethod"] {
                #expect(!text.contains(marker), "\(file.lastPathComponent) contains \(marker)")
            }
        }
    }
}
