import AppKit
import Darwin
import Foundation
import IOKit
import os

nonisolated enum CPUReader {
    static let name: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown CPU" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "Unknown CPU" }
        return String(cString: bytes)
    }()

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


nonisolated enum MemoryReader {
    static func pressureFraction(availableLevel: Int?) -> Double? {
        availableLevel.flatMap { (0...100).contains($0) ? Double(100 - $0) / 100 : nil }
    }
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
            pressure: MemoryPressure(rawValue: level) ?? .normal,
            pressureFraction: pressureFraction(availableLevel: sysctlInt("kern.memorystatus_level"))
        )
    }
}

// MARK: - Disk and network throughput


nonisolated enum DiskIOReader {
    /// Bytes read and written by every disk since startup.
    static func counters() -> ByteCounters {
        devices().reduce(into: ByteCounters()) { total, device in
            total.read &+= device.counters.read
            total.written &+= device.counters.written
        }
    }

    static func devices() -> [DriveCounters] {
        var devices: [DriveCounters] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            var identifier: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &identifier)
            devices.append(DriveCounters(id: String(identifier), counters: ByteCounters(
                read: (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                written: (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0)))
        }
        return devices
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


/// Additional temperature sensors through the HID event system. CPU temperatures use the SMC.
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
    private let library: UnsafeMutableRawPointer?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        library = handle
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

    deinit { if let library { dlclose(library) } }

    /// Only the sensors `TemperatureSample.from` groups: each one read costs a call to the HID
    /// event system on every sample, and most of the dozens reported are never shown.
    static func isUsed(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["tdie", "cpu", "pacc", "eacc", "gpu", "gacc", "nand", "ssd", "battery"].contains { lower.contains($0) }
    }

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


nonisolated enum BatteryReader {
    static func read(maximumCapacity: Double? = nil) -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              !properties.isEmpty else { return nil }
        return sample(properties: properties, maximumCapacity: maximumCapacity)
    }

    static func sample(properties: [String: Any], maximumCapacity: Double? = nil) -> BatterySample? {

        // Capacity figures sit at the top level on some Macs and inside BatteryData on others.
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? {
            (properties[key] as? NSNumber ?? nested[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
        }
        guard let current = value("CurrentCapacity"), let maximum = value("MaxCapacity"), maximum > 0 else { return nil }

        let charging = properties["IsCharging"] as? Bool ?? false
        let minutes = charging ? value("AvgTimeToFull") : value("AvgTimeToEmpty")
        let electrical = BatterySample.electrical(voltageMillivolts: value("Voltage"), milliamps: value("Amperage"))
        let pluggedIn = properties["ExternalConnected"] as? Bool ?? false
        let adapter = pluggedIn ? properties["AdapterDetails"] as? [String: Any] ?? [:] : [:]
        let charger = properties["ChargerData"] as? [String: Any] ?? [:]
        func capacity(_ value: Int?) -> Int? { value.flatMap { (1...100_000).contains($0) ? $0 : nil } }
        let temperature = value("Temperature").map { Double($0) / 100 }.flatMap { (1...100).contains($0) ? $0 : nil }
        return BatterySample(
            percent: min(max(maximum == 100 ? current : Int(Double(current) / Double(maximum) * 100), 0), 100),
            isCharging: charging,
            isPluggedIn: pluggedIn,
            cycleCount: value("CycleCount"),
            // The "Maximum Capacity" System Settings shows, so the two agree; the ratio of
            // capacities runs a few percent lower and is only the fallback.
            health: maximumCapacity
                ?? BatterySample.health(fullCharge: value("NominalChargeCapacity") ?? value("AppleRawMaxCapacity"),
                                        design: value("DesignCapacity")),
            minutesRemaining: minutes.flatMap { $0 > 0 && $0 < 65_535 ? $0 : nil },
            voltage: electrical.voltage, amperage: electrical.current,
            currentCapacityMah: capacity(value("AppleRawCurrentCapacity") ?? value("RemainingCapacity")),
            fullChargeCapacityMah: capacity(value("AppleRawMaxCapacity") ?? value("FullChargeCapacity") ?? value("NominalChargeCapacity")),
            designCapacityMah: capacity(value("DesignCapacity")), temperatureCelsius: temperature,
            adapterWatts: capacity(adapter["Watts"] as? Int),
            adapterVoltage: (adapter["AdapterVoltage"] as? Int).flatMap { BatterySample.electrical(voltageMillivolts: $0, milliamps: nil).voltage },
            adapterAmperage: (adapter["Current"] as? Int).flatMap { BatterySample.electrical(voltageMillivolts: nil, milliamps: $0).current },
            isFullyCharged: properties["FullyCharged"] as? Bool ?? false,
            isChargingPaused: pluggedIn && !charging && current < maximum && (charger["NotChargingReason"] as? Int ?? 0) != 0
        )
    }
}


/// Battery "Maximum Capacity" as System Settings › Battery shows it, from `system_profiler`
/// (about 50 ms), read at most every 30 minutes since it changes over months.
nonisolated enum BatteryHealthReader {
    private static let cache = OSAllocatedUnfairLock<(date: Date, value: Double?)?>(initialState: nil)

    static func maximumCapacity() async -> Double? {
        if let cached = cache.withLock({ $0 }), Date().timeIntervalSince(cached.date) < 1_800 { return cached.value }
        let command = ToolCommand(executable: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                                  arguments: ["SPPowerDataType", "-json"])
        let output = try? await ProcessCommandRunner(stopsWhenCancelled: true, maximumOutputBytes: 1_048_576)
            .run(command, timeout: 5)
        guard !Task.isCancelled else { return nil }
        let value = output.flatMap { $0.succeeded ? parse(Data($0.stdout.utf8)) : nil }
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

}

// MARK: - Processes


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
