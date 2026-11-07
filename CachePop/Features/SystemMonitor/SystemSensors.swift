import AppKit
import Darwin
import Foundation
import IOKit
import os

// Read-only readers for System Monitor. Each one uses a public Mach or IOKit interface, except
// temperatures (IOHIDEventSystem) and fans (the SMC), which have no public API and are read the
// way Activity Monitor-style tools do. Nothing here changes the system.

// MARK: - CPU

nonisolated struct CPUTicks: Sendable, Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
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

nonisolated enum CPUReader {
    static func ticks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(MachHost.port, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(count)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            return CPUTicks(
                user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            )
        }
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }

    /// Performance and efficiency core counts on Apple silicon.
    static func coreKinds() -> (performance: Int, efficiency: Int) {
        (sysctlInt("hw.perflevel0.logicalcpu") ?? 0, sysctlInt("hw.perflevel1.logicalcpu") ?? 0)
    }
}

// MARK: - Memory

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

    /// What Activity Monitor calls "Memory Used".
    var used: Int64 { app + wired + compressed }
    var free: Int64 { max(total - used - cached, 0) }
    var usedFraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }

    /// Activity Monitor's arithmetic, from page counts.
    static func from(
        total: Int64, pageSize: Int64, internalPages: Int64, purgeablePages: Int64, externalPages: Int64,
        wiredPages: Int64, compressorPages: Int64, swapUsed: Int64, pressure: MemoryPressure
    ) -> MemorySample {
        MemorySample(
            total: total,
            app: max(internalPages - purgeablePages, 0) * pageSize,
            wired: wiredPages * pageSize,
            compressed: compressorPages * pageSize,
            cached: (externalPages + purgeablePages) * pageSize,
            swapUsed: swapUsed,
            pressure: pressure
        )
    }
}

nonisolated enum MemoryReader {
    static func read() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(MachHost.port, HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return MemorySample(total: total) }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        let level = sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1

        return MemorySample.from(
            total: total,
            pageSize: Int64(vm_kernel_page_size),
            internalPages: Int64(stats.internal_page_count),
            purgeablePages: Int64(stats.purgeable_count),
            externalPages: Int64(stats.external_page_count),
            wiredPages: Int64(stats.wire_count),
            compressorPages: Int64(stats.compressor_page_count),
            swapUsed: Int64(swap.xsu_used),
            pressure: MemoryPressure(rawValue: level) ?? .normal
        )
    }
}

// MARK: - Disk and network throughput

nonisolated struct ByteCounters: Sendable, Equatable {
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

nonisolated enum DiskIOReader {
    /// Bytes read and written by every disk since startup.
    static func counters() -> ByteCounters {
        var counters = ByteCounters()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return counters
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            counters.read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            counters.written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return counters
    }
}

nonisolated enum NetworkReader {
    /// Bytes received and sent on Wi-Fi and Ethernet since startup. `read` is received.
    static func counters() -> ByteCounters {
        var counters = ByteCounters()
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return counters }
        defer { freeifaddrs(addresses) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            if let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               String(cString: entry.ifa_name).hasPrefix("en"),
               let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) {
                counters.read += UInt64(data.pointee.ifi_ibytes)
                counters.written += UInt64(data.pointee.ifi_obytes)
            }
            pointer = entry.ifa_next
        }
        return counters
    }
}

// MARK: - Temperatures

nonisolated struct TemperatureSample: Sendable, Equatable {
    /// Average of the chip's die sensors.
    var chip: Double?
    /// Hottest die sensor.
    var chipMax: Double?
    var ssd: Double?
    var battery: Double?

    /// Groups raw sensor readings: Apple silicon reports "PMU tdie…" for the chip, "NAND…" for the
    /// SSD and "gas gauge battery" for the battery. Readings outside 1–130 °C are sensor noise.
    static func from(_ readings: [(name: String, celsius: Double)]) -> TemperatureSample {
        let valid = readings.filter { $0.celsius > 1 && $0.celsius < 130 }
        func average(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let lower = valid.map { (name: $0.name.lowercased(), celsius: $0.celsius) }
        var die = lower.filter { $0.name.contains("tdie") }.map(\.celsius)
        // Intel Macs and older names: "CPU …" sensors.
        if die.isEmpty { die = lower.filter { $0.name.contains("cpu") || $0.name.contains("pacc") || $0.name.contains("eacc") }.map(\.celsius) }
        return TemperatureSample(
            chip: average(die),
            chipMax: die.max(),
            ssd: average(lower.filter { $0.name.contains("nand") || $0.name.contains("ssd") }.map(\.celsius)),
            battery: average(lower.filter { $0.name.contains("battery") }.map(\.celsius))
        )
    }
}

/// Temperature sensors through the HID event system, the only way to read them on Apple silicon.
nonisolated final class TemperatureReader: @unchecked Sendable {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?
    private typealias SetMatching = @convention(c) (IOHIDEventSystemClient, CFDictionary) -> Int32
    private typealias CopyEvent = @convention(c) (IOHIDServiceClient, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private let copyEvent: CopyEvent?
    private let getFloat: GetFloat?
    /// Kept alive for as long as the reader: its services are only valid while it exists.
    private let client: IOHIDEventSystemClient?
    /// Each sensor with its name, read once.
    private let services: [(service: IOHIDServiceClient, name: String)]
    private let lock = NSLock()

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        let create = dlsym(handle, "IOHIDEventSystemClientCreate").map { unsafeBitCast($0, to: Create.self) }
        let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching").map { unsafeBitCast($0, to: SetMatching.self) }
        copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent").map { unsafeBitCast($0, to: CopyEvent.self) }
        getFloat = dlsym(handle, "IOHIDEventGetFloatValue").map { unsafeBitCast($0, to: GetFloat.self) }

        guard let create, let setMatching, let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            self.client = nil
            services = []
            return
        }
        self.client = client
        // Apple's vendor page, temperature usage.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let found = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        services = found.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  TemperatureReader.isUsed(name) else { return nil }
            return (service: service, name: name)
        }
    }

    /// Only the sensors `TemperatureSample.from` groups: each one read costs a call to the HID
    /// event system on every sample, and most of the dozens reported are never shown.
    static func isUsed(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["tdie", "cpu", "pacc", "eacc", "nand", "ssd", "battery"].contains { lower.contains($0) }
    }

    var isAvailable: Bool { !services.isEmpty && copyEvent != nil && getFloat != nil }

    func readings() -> [(name: String, celsius: Double)] {
        guard client != nil, let copyEvent, let getFloat else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return services.compactMap { entry in
            guard let event = copyEvent(entry.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return (entry.name, getFloat(event, Self.temperatureField))
        }
    }

    func read() -> TemperatureSample { .from(readings()) }
}

// MARK: - Fans

// Fan readings come from `SMC` in CachePopShared, which the fan helper uses too.

// MARK: - Battery

nonisolated struct BatterySample: Sendable, Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var cycleCount: Int?
    /// Full-charge capacity as a share of the original.
    var health: Double?
    /// Minutes until empty (on battery) or full (charging), when macOS has an estimate.
    var minutesRemaining: Int?

    static func health(fullCharge: Int?, design: Int?) -> Double? {
        guard let fullCharge, let design, design > 0, fullCharge > 0 else { return nil }
        return min(Double(fullCharge) / Double(design), 1)
    }
}

nonisolated enum BatteryReader {
    static func read() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let current = properties["CurrentCapacity"] as? Int,
              let maximum = properties["MaxCapacity"] as? Int, maximum > 0 else { return nil }

        // Capacity figures sit at the top level on some Macs and inside BatteryData on others.
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? { properties[key] as? Int ?? nested[key] as? Int }

        let charging = properties["IsCharging"] as? Bool ?? false
        let minutes = charging ? value("AvgTimeToFull") : value("AvgTimeToEmpty")
        return BatterySample(
            percent: maximum == 100 ? current : Int(Double(current) / Double(maximum) * 100),
            isCharging: charging,
            isPluggedIn: properties["ExternalConnected"] as? Bool ?? false,
            cycleCount: value("CycleCount"),
            // The "Maximum Capacity" System Settings shows, so the two agree; the ratio of
            // capacities runs a few percent lower and is only the fallback.
            health: BatteryHealthReader.maximumCapacity()
                ?? BatterySample.health(fullCharge: value("NominalChargeCapacity") ?? value("AppleRawMaxCapacity"),
                                        design: value("DesignCapacity")),
            minutesRemaining: minutes.flatMap { $0 > 0 && $0 < 65_535 ? $0 : nil }
        )
    }
}

/// Battery "Maximum Capacity" as System Settings › Battery shows it, from `system_profiler`
/// (about 50 ms), read at most every 30 minutes since it changes over months.
nonisolated enum BatteryHealthReader {
    private static let cache = OSAllocatedUnfairLock<(date: Date, value: Double?)?>(initialState: nil)

    static func maximumCapacity() -> Double? {
        if let cached = cache.withLock({ $0 }), Date().timeIntervalSince(cached.date) < 1_800 { return cached.value }
        let value = run().flatMap(parse)
        cache.withLock { $0 = (Date(), value) }
        return value
    }

    /// Reads "sppower_battery_health_maximum_capacity" ("90%") from `system_profiler -json`.
    static func parse(_ data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            guard let health = section["sppower_battery_health_info"] as? [String: Any],
                  let text = health["sppower_battery_health_maximum_capacity"] as? String,
                  let percent = Double(text.filter { $0.isNumber || $0 == "." }), percent > 0, percent <= 100 else { continue }
            return percent / 100
        }
        return nil
    }

    private static func run() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        // The output is a few KB, well under the pipe's buffer, so waiting first can't stall it.
        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? data : nil
    }
}

// MARK: - Processes

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

nonisolated enum MachHost {
    /// Taken once: every `mach_host_self()` call adds a reference to the port that is never
    /// given back, so calling it on each sample leaks one per reading.
    static let port = mach_host_self()
}

nonisolated func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
        var wide: Int64 = 0
        var wideSize = MemoryLayout<Int64>.size
        return sysctlbyname(name, &wide, &wideSize, nil, 0) == 0 ? Int(wide) : nil
    }
    return Int(value)
}
