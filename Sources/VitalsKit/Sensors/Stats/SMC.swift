//
//  smc.swift
//  SMC
//
//  Created by Serhiy Mytrovtsiy on 25/05/2021.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2021 Serhiy Mytrovtsiy. All rights reserved.
//
//  Adapted for Vitals from Stats (https://github.com/exelban/stats, MIT License, see LICENSE in this folder).
//  Only the read path is kept: key info, read bytes, value decoding and fan speeds.
//  The Apple Silicon temperature key table is adapted from Stats' Modules/Sensors/values.swift (SensorKeys.swift).
//  Vitals never writes to the SMC, so the write selectors and fan-control code were left out on purpose.
//

import Foundation
import IOKit

public enum SMCValue {
    /// Apple Silicon reports temperatures and fan speeds as little-endian Float32 ("flt "); older keys use
    /// big-endian unsigned ints and the 14.2 fixed-point "fpe2". Anything else isn't needed and decodes to nil.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }
}

/// One fan as the SMC reports it. Read-only: Vitals shows fan speed and never sets it.
public struct FanReading: Equatable, Sendable {
    public var index: Int
    public var rpm: Double
    public var min: Double?
    public var max: Double?

    public init(index: Int, rpm: Double, min: Double?, max: Double?) {
        self.index = index
        self.rpm = rpm
        self.min = min
        self.max = max
    }
}

/// Mirrors the kernel's SMCKeyData_t, so the field order and sizes must not change.
struct SMCKeyData {
    typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// Read-only AppleSMC connection. Opened on first use, so a hidden Temps item never touches the SMC.
public final class SMC {
    /// The struct-method selector, and the two read commands it accepts. Nothing else is ever sent.
    private enum Command {
        static let selector: UInt32 = 2
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0
    private var opened = false
    private var keyInfoCache: [UInt32: SMCKeyData.KeyInfo] = [:]

    public init() {}

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func value(_ key: String) -> Double? {
        guard let raw = read(key) else { return nil }
        return SMCValue.decode(type: raw.type, bytes: raw.bytes)
    }

    public func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard key.utf8.count == 4, connect() else { return nil }
        var input = SMCKeyData()
        input.key = Self.fourCharCode(key)

        let info: SMCKeyData.KeyInfo
        if let cached = keyInfoCache[input.key] {
            info = cached
        } else {
            input.data8 = Command.readKeyInfo
            guard let output = call(&input), output.keyInfo.dataSize > 0, output.keyInfo.dataSize <= 32 else { return nil }
            info = output.keyInfo
        }

        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readBytes
        guard let output = call(&input) else {
            keyInfoCache.removeValue(forKey: input.key)
            return nil
        }
        keyInfoCache[input.key] = info
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (Self.string(info.dataType), bytes)
    }

    public func fans() -> [FanReading] {
        guard let count = value("FNum"), count > 0 else { return [] }
        return (0..<min(Int(count), 10)).map { i in
            FanReading(index: i, rpm: value("F\(i)Ac") ?? 0, min: value("F\(i)Mn"), max: value("F\(i)Mx"))
        }
    }

    private func connect() -> Bool {
        if opened { return connection != 0 }
        opened = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess { connection = 0 }
        return connection != 0
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, Command.selector, &input, MemoryLayout<SMCKeyData>.stride,
                                               &output, &outputSize)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private static func fourCharCode(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(code >> $0 & 0xff) }, as: UTF8.self)
    }
}
