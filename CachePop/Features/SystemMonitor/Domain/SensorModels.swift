import Foundation

nonisolated struct CPUTicks: Sendable, Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}


nonisolated struct CPUSample: Sendable, Equatable {
    /// 0…1 across all cores.
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    /// 0…1 per core.
    var perCore: [Double] = []

    /// Usage between two readings of each core's tick counters.
    static func between(_ previous: [CPUTicks], _ current: [CPUTicks]) -> CPUSample {
        guard previous.count == current.count, !current.isEmpty else { return CPUSample() }
        var sample = CPUSample()
        var user: UInt64 = 0, system: UInt64 = 0, busy: UInt64 = 0, total: UInt64 = 0
        for (old, new) in zip(previous, current) {
            let coreUser = delta(old.user, new.user), coreSystem = delta(old.system, new.system)
            let coreNice = delta(old.nice, new.nice), coreIdle = delta(old.idle, new.idle)
            let coreBusy = coreUser + coreSystem + coreNice
            let coreTotal = coreBusy + coreIdle
            sample.perCore.append(coreTotal > 0 ? min(Double(coreBusy) / Double(coreTotal), 1) : 0)
            user += coreUser + coreNice
            system += coreSystem
            busy += coreBusy
            total += coreTotal
        }
        guard total > 0 else { return sample }
        sample.total = min(Double(busy) / Double(total), 1)
        sample.user = Double(user) / Double(total)
        sample.system = Double(system) / Double(total)
        return sample
    }

    /// Ticks between two readings of one of macOS's 32-bit counters, across a wrap (each wraps
    /// after about 497 days). A plain 64-bit difference would come out near 2⁶⁴ there, and adding
    /// it up would overflow and crash.
    private static func delta(_ old: UInt64, _ new: UInt64) -> UInt64 {
        UInt64(UInt32(truncatingIfNeeded: new &- old))
    }
}


nonisolated enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Under pressure"
        case .critical: "Critical"
        }
    }
}


nonisolated struct MemorySample: Sendable, Equatable {
    var total: Int64 = 0
    /// Memory apps are using ("App Memory" in Activity Monitor).
    var app: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
    /// Files kept in memory for speed; given back as soon as apps need it.
    var cached: Int64 = 0
    var swapUsed: Int64 = 0
    var pressure: MemoryPressure = .normal
    var pressureFraction: Double? = nil

    /// What Activity Monitor calls "Memory Used".
    var used: Int64 { app + wired + compressed }
    var free: Int64 { max(total - used - cached, 0) }
    var usedFraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }

    /// Activity Monitor's arithmetic, from page counts.
    static func from(
        total: Int64, pageSize: Int64, internalPages: Int64, purgeablePages: Int64, externalPages: Int64,
        wiredPages: Int64, compressorPages: Int64, swapUsed: Int64, pressure: MemoryPressure, pressureFraction: Double? = nil
    ) -> MemorySample {
        MemorySample(
            total: total,
            app: max(internalPages - purgeablePages, 0) * pageSize,
            wired: wiredPages * pageSize,
            compressed: compressorPages * pageSize,
            cached: (externalPages + purgeablePages) * pageSize,
            swapUsed: swapUsed,
            pressure: pressure, pressureFraction: pressureFraction
        )
    }
}


nonisolated struct ByteCounters: Codable, Sendable, Equatable {
    var read: UInt64 = 0
    var written: UInt64 = 0
}


nonisolated struct Throughput: Sendable, Equatable {
    var inPerSecond: Double = 0
    var outPerSecond: Double = 0

    static func between(_ previous: ByteCounters, _ current: ByteCounters, seconds: Double) -> Throughput {
        guard seconds > 0 else { return Throughput() }
        // Counters can reset (a disk ejected, an interface gone); never report negative rates.
        let read = current.read >= previous.read ? Double(current.read - previous.read) : 0
        let written = current.written >= previous.written ? Double(current.written - previous.written) : 0
        return Throughput(inPerSecond: read / seconds, outPerSecond: written / seconds)
    }
}


nonisolated struct DriveCounters: Sendable, Equatable {
    let id: String
    let counters: ByteCounters
}


nonisolated struct DriveActivity: Sendable, Equatable {
    let id: String
    let counters: ByteCounters
    let throughput: Throughput
}


nonisolated struct TemperatureSample: Sendable, Equatable {
    /// CPU core average (or the CPU die sensor on Intel).
    var chip: Double?
    /// Hottest valid CPU sensor, used by fan safety checks.
    var chipMax: Double?
    var ssd: Double?
    var battery: Double?
    /// From the SMC, not the HID sensors (see `MemoryTemperature`). nil where there's no sensor.
    var memory: Double?
    var sensors: [TemperatureSensor] = []
    var gpu: Double? = nil

    /// Groups raw HID readings. Generic PMU die sensors are retained individually, but are not
    /// CPU sensors. Prefer the CPU-specific SMC reading when available.
    static func from(_ readings: [(name: String, celsius: Double)]) -> TemperatureSample {
        let valid = readings.filter { $0.celsius > 1 && $0.celsius < 130 }
        func average(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let lower = valid.map { (name: $0.name.lowercased(), celsius: $0.celsius) }
        let die = lower.filter { SensorGroup.classify($0.name) == .cpu && (10...120).contains($0.celsius) }.map(\.celsius)
        var occurrences: [String: Int] = [:]
        return TemperatureSample(
            chip: average(die),
            chipMax: die.max(),
            ssd: average(lower.filter { $0.name.contains("nand") || $0.name.contains("ssd") }.map(\.celsius)),
            battery: average(lower.filter { $0.name.contains("battery") }.map(\.celsius)),
            sensors: valid.map { sensor in
                let occurrence = occurrences[sensor.name, default: 0]
                occurrences[sensor.name] = occurrence + 1
                return TemperatureSensor(id: "hid.\(sensor.name).\(occurrence)", name: sensor.name,
                                         group: .classify(sensor.name), celsius: sensor.celsius)
            }
        )
    }

    mutating func applyCPU(_ reading: CPUTemperature.Reading?) {
        guard let reading else { return }
        chip = reading.average
        chipMax = max(chipMax ?? reading.maximum, reading.maximum)
        sensors.insert(contentsOf: reading.sensors, at: 0)
    }
}


/// The memory's temperature, which only the SMC reports. Its sensor names differ from chip to
/// chip, so CachePop looks for them once among all of the SMC's keys.
nonisolated enum MemoryTemperature {
    /// Apple silicon names memory sensors "Tm" and a digit (Tm02 on M1, Tm0B on M4, Tm0p on M4
    /// Pro), though "Tm0P" is the mainboard. Intel Macs use "TM0P" and memory riser slots "TMA1".
    static func keys(in keys: [String]) -> [String] {
        keys.filter { key in
            let c = Array(key)
            guard c.count == 4, c[0] == "T" else { return false }
            switch c[1] {
            case "m": return c[2].isNumber && c[3] != "P"
            case "M": return (c[2].isNumber && "PS".contains(c[3])) || ("AB".contains(c[2]) && c[3].isNumber)
            default: return false
            }
        }
    }

    /// The sensors' average, leaving out readings outside 1–130 °C (sensor noise).
    static func average(_ readings: [Double]) -> Double? {
        let valid = readings.filter { $0 > 1 && $0 < 130 }
        return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
    }
}


nonisolated struct BatterySample: Sendable, Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var cycleCount: Int?
    /// Full-charge capacity as a share of the original.
    var health: Double?
    /// Minutes until empty (on battery) or full (charging), when macOS has an estimate.
    var minutesRemaining: Int?
    var voltage: Double? = nil
    var amperage: Double? = nil
    var currentCapacityMah: Int? = nil
    var fullChargeCapacityMah: Int? = nil
    var designCapacityMah: Int? = nil
    var temperatureCelsius: Double? = nil
    var adapterWatts: Int? = nil
    var adapterVoltage: Double? = nil
    var adapterAmperage: Double? = nil
    var isFullyCharged = false
    var isChargingPaused = false
    var powerWatts: Double? {
        guard let voltage, let amperage else { return nil }
        return abs(voltage * amperage)
    }

    static func electrical(voltageMillivolts: Int?, milliamps: Int?) -> (voltage: Double?, current: Double?) {
        let volts = voltageMillivolts.flatMap { (1...50_000).contains($0) ? Double($0) / 1_000 : nil }
        let amps = milliamps.flatMap { (-30_000...30_000).contains($0) ? Double($0) / 1_000 : nil }
        return (volts, amps)
    }

    static func health(fullCharge: Int?, design: Int?) -> Double? {
        guard let fullCharge, let design, design > 0, fullCharge > 0 else { return nil }
        return min(Double(fullCharge) / Double(design), 1)
    }
}


nonisolated struct ProcessUsage: Sendable, Equatable, Identifiable {
    let pid: Int32
    let name: String
    /// Percent of one core, as `ps` and Activity Monitor report it.
    let cpuPercent: Double
    let memoryBytes: Int64

    var id: Int32 { pid }
}


nonisolated enum ProcessListParser {
    /// Parses `ps -Ao pid=,pcpu=,rss=,comm=`. `comm` is a path and may contain spaces.
    static func parse(_ output: String) -> [ProcessUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rss = Int64(parts[2]) else { return nil }
            let path = String(parts[3]).trimmingCharacters(in: .whitespaces)
            // NSString, not URL(fileURLWithPath:), which checks the disk for each of hundreds of lines.
            return ProcessUsage(pid: pid, name: (path as NSString).lastPathComponent, cpuPercent: cpu, memoryBytes: rss * 1024)
        }
    }
}

// MARK: - Helpers
