import Darwin

struct CoreTicks: Equatable {
    var user, system, idle, nice: UInt32
}

enum CoreKind: Equatable {
    case efficiency, performance

    var title: String { self == .efficiency ? "Efficiency" : "Performance" }
}

enum CPULoad {
    /// Busy share of the ticks elapsed between two reads, 0...100.
    /// The total weights each core by its ticks rather than averaging per-core percentages.
    static func usage(previous: [CoreTicks], current: [CoreTicks]) -> (total: Double, perCore: [Double]) {
        guard previous.count == current.count, !current.isEmpty else { return (0, []) }
        var busySum = 0.0, allSum = 0.0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        for (p, c) in zip(previous, current) {
            // The kernel's counters are 32-bit and wrap; wrapping subtraction keeps the delta right across a wrap.
            let busy = Double(c.user &- p.user) + Double(c.system &- p.system) + Double(c.nice &- p.nice)
            let all = busy + Double(c.idle &- p.idle)
            busySum += busy
            allSum += all
            perCore.append(all > 0 ? busy / all * 100 : 0)
        }
        return (allSum > 0 ? busySum / allSum * 100 : 0, perCore)
    }

    /// Apple Silicon numbers its efficiency cores first.
    static func coreKinds(performance: Int, efficiency: Int) -> [CoreKind] {
        Array(repeating: .efficiency, count: max(0, efficiency)) + Array(repeating: .performance, count: max(0, performance))
    }

    static func coreKindsOfThisMac() -> [CoreKind] {
        coreKinds(performance: sysctlInt("hw.perflevel0.logicalcpu"), efficiency: sysctlInt("hw.perflevel1.logicalcpu"))
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
    }
}

enum CPUTicks {
    static func read() -> [CoreTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(count)).map { core in
            let base = Int(CPU_STATE_MAX) * core
            func state(_ s: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(s)]) }
            return CoreTicks(user: state(CPU_STATE_USER), system: state(CPU_STATE_SYSTEM),
                             idle: state(CPU_STATE_IDLE), nice: state(CPU_STATE_NICE))
        }
    }
}
