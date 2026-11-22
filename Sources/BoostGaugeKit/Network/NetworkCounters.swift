import Darwin
import Foundation
import SystemConfiguration

public struct IfCounters: Equatable, Sendable {
    public var ibytes: UInt64
    public var obytes: UInt64

    public init(ibytes: UInt64, obytes: UInt64) {
        self.ibytes = ibytes
        self.obytes = obytes
    }
}

public enum NetworkCounters {
    /// Byte counters for every interface, from one in-process sysctl (about 2 ms, no subprocess).
    /// NET_RT_IFLIST2 is the variant with 64-bit counters; the plain list wraps at 4 GB.
    public static func snapshot() -> [String: IfCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: IfCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                defer { offset += Int(header.ifm_msglen) }
                // Every bound is this message's own end, so a short message can't borrow the next one's bytes.
                let end = min(length, offset + Int(header.ifm_msglen))
                let link = offset + MemoryLayout<if_msghdr2>.size
                let nameStart = link + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!
                guard Int32(header.ifm_type) == RTM_IFINFO2, nameStart <= end else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                // The interface's link-level address follows the header and carries its name.
                let nameLength = Int(raw[link + 5])  // sockaddr_dl.sdl_nlen
                let nameEnd = nameStart + nameLength
                guard nameLength > 0, nameEnd <= end else { continue }
                let name = String(decoding: raw[nameStart..<nameEnd], as: UTF8.self)
                result[name] = IfCounters(ibytes: message.ifm_data.ifi_ibytes, obytes: message.ifm_data.ifi_obytes)
            }
        }
        return result
    }

    /// Only en* (Wi-Fi, Ethernet, USB and Thunderbolt adapters, iPhone tethering) is counted. Loopback never
    /// leaves the Mac, and tunnels (VPNs such as Tailscale), bridges (VMs, Thunderbolt Bridge) and peer-to-peer
    /// Wi-Fi (awdl, llw) carry traffic that also crosses an en* interface, so counting them would double it.
    static func counts(_ name: String) -> Bool {
        name.hasPrefix("en")
    }

    /// Bytes per second summed over counted interfaces. An interface that's new this tick, or whose counters went
    /// down (it bounced, or the Mac woke from a reset), adds nothing rather than a bogus spike.
    public static func rates(previous: [String: IfCounters], current: [String: IfCounters],
                             elapsed: TimeInterval) -> (up: Double, down: Double) {
        guard elapsed > 0 else { return (0, 0) }
        var up: UInt64 = 0, down: UInt64 = 0
        for (name, now) in current where counts(name) {
            guard let before = previous[name] else { continue }
            if now.ibytes >= before.ibytes { down += now.ibytes - before.ibytes }
            if now.obytes >= before.obytes { up += now.obytes - before.obytes }
        }
        return (Double(up) / elapsed, Double(down) / elapsed)
    }

    /// Menu bar form: "12K", "1.2M", "120M", "1.5G" (bytes/s), or "96Kb", "9.6Mb" (bits/s). Decimal units, as macOS uses.
    public static func compact(_ bytesPerSecond: Double, unit: NetworkUnit = .bytes) -> String {
        let (number, prefix) = scaled(bytesPerSecond, unit)
        return number + prefix + (unit == .bits ? "b" : "")
    }

    /// Panel form: "12 KB/s", "1.2 MB/s", "9.6 Mb/s".
    public static func rateText(_ bytesPerSecond: Double, unit: NetworkUnit) -> String {
        let (number, prefix) = scaled(bytesPerSecond, unit)
        return "\(number) \(prefix)\(unit == .bits ? "b" : "B")/s"
    }

    /// Whole numbers from 10 up and one decimal below, switching unit where rounding would print "1000".
    static func scaled(_ bytesPerSecond: Double, _ unit: NetworkUnit) -> (number: String, prefix: String) {
        let value = max(0, bytesPerSecond) * (unit == .bits ? 8 : 1)
        if value < 999_500 { return ("\(Int((value / 1e3).rounded()))", "K") }
        for (scale, prefix) in [(1e6, "M"), (1e9, "G")] {
            let v = value / scale
            if v < 9.95 { return (String(format: "%.1f", v), prefix) }
            if v < 999.5 || prefix == "G" { return ("\(Int(v.rounded()))", prefix) }
        }
        return ("0", "K")
    }
}

/// The interface macOS currently routes through, as System Settings names it.
public struct NetworkConnection: Equatable, Sendable {
    public var service: String
    public var interface: String
    public var address: String?

    public init(service: String, interface: String, address: String?) {
        self.service = service
        self.interface = interface
        self.address = address
    }

    /// Reads configd's dynamic store in-process. Panel-only, a few small IPC round trips.
    public static func primary() -> NetworkConnection? {
        guard let store = SCDynamicStoreCreate(nil, "BoostGauge" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interface = global["PrimaryInterface"] as? String else { return nil }
        let service = (global["PrimaryService"] as? String).flatMap {
            (SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\($0)" as CFString) as? [String: Any])?["UserDefinedName"] as? String
        }
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(interface)/IPv4" as CFString) as? [String: Any]
        let address = (ipv4?["Addresses"] as? [String])?.first
        return NetworkConnection(service: service ?? interface, interface: interface, address: address)
    }
}
