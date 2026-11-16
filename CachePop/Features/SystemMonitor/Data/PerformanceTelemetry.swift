import Darwin
import Foundation
import IOKit

/// One subscription sampled by the existing monitor loop. No timer, subprocess or sleep.
/// IOReport is optional/private; missing channels remain unavailable.
nonisolated final class PerformanceTelemetry {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias Merge = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Int32
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias Sample = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Delta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Name = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Integer = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias Count = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?

    private let library: UnsafeMutableRawPointer?
    private let sample: Sample?
    private let delta: Delta?
    private let channelName: Name?
    private let groupName: Name?
    private let unitName: Name?
    private let integer: Integer?
    private let stateCount: Count?
    private let stateName: StateName?
    private let residency: Integer?
    private var channels: CFMutableDictionary?
    private var subscription: CFTypeRef?
    private var previous: CFDictionary?
    private var previousDate: ContinuousClock.Instant?
    private var liveEnergyChannels: Set<String> = []
    private let efficiency: [Double]
    private let performance: [Double]

    init() {
        let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
        library = handle
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        sample = symbol("IOReportCreateSamples", Sample.self)
        delta = symbol("IOReportCreateSamplesDelta", Delta.self)
        channelName = symbol("IOReportChannelGetChannelName", Name.self)
        groupName = symbol("IOReportChannelGetGroup", Name.self)
        unitName = symbol("IOReportChannelGetUnitLabel", Name.self)
        integer = symbol("IOReportSimpleGetIntegerValue", Integer.self)
        stateCount = symbol("IOReportStateGetCount", Count.self)
        stateName = symbol("IOReportStateGetNameForIndex", StateName.self)
        residency = symbol("IOReportStateGetResidency", Integer.self)
        let tables = Self.frequencyTables()
        efficiency = tables.0
        performance = tables.1
        guard let copy = symbol("IOReportCopyChannelsInGroup", CopyChannels.self),
              let merge = symbol("IOReportMergeChannels", Merge.self),
              let subscribe = symbol("IOReportCreateSubscription", Subscribe.self) else { return }
        var merged: CFMutableDictionary?
        let groups: [(String, String?)] = [("CPU Stats", "CPU Core Performance States"), ("Energy Model", nil)]
            + ["DCP", "DCP0", "DCPEXT0", "DCPEXT1", "DCPEXT2", "DCPEXT3"].map { ($0, "swap") }
        for (group, subgroup) in groups {
            guard let copied = copy(group as CFString, subgroup.map { $0 as CFString }, 0, 0, 0)?.takeRetainedValue(),
                  let values = copied as? [String: Any], let items = values["IOReportChannels"] as? [Any], !items.isEmpty else { continue }
            if let current = merged { _ = merge(current, copied, nil) }
            else { merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, copied) }
        }
        guard let merged else { return }
        var subscribed: Unmanaged<CFMutableDictionary>?
        subscription = subscribe(nil, merged, &subscribed, 0, nil)?.takeRetainedValue()
        channels = subscribed?.takeRetainedValue() ?? merged
    }

    deinit {
        // Release all CF objects while their library is still loaded.
        previous = nil
        subscription = nil
        channels = nil
        if let library { dlclose(library) }
    }

    func read(at now: ContinuousClock.Instant = .now) -> PerformanceSample {
        guard let subscription, let channels, let sample, let delta,
              let current = sample(subscription, channels, nil)?.takeRetainedValue() else { return PerformanceSample() }
        defer { previous = current; previousDate = now }
        guard let previous, let previousDate else { return PerformanceSample() }
        let elapsed = previousDate.duration(to: now).secondsValue
        let key = "IOReportChannels" as CFString
        guard elapsed > 0, elapsed <= 10,
              let difference = delta(previous, current, nil)?.takeRetainedValue(),
              let array = CFDictionaryGetValue(difference, Unmanaged.passUnretained(key).toOpaque()) else { return PerformanceSample() }
        let items = unsafeBitCast(array, to: CFArray.self)
        var result = PerformanceSample()
        var e: [Double] = [], p: [Double] = []
        var frameCount: Int64 = 0
        var hasFrames = false
        // IOReport caches metadata inside the channel dictionary. Preserve its original
        // mutable CF objects; bridging through a Swift Dictionary makes an immutable copy.
        for index in 0..<CFArrayGetCount(items) {
            let value = unsafeBitCast(CFArrayGetValueAtIndex(items, index), to: CFDictionary.self)
            let name = channelName?(value)?.takeUnretainedValue() as String? ?? ""
            let group = groupName?(value)?.takeUnretainedValue() as String? ?? ""
            if group == "CPU Stats" {
                if name.contains("ECPU"), let frequency = frequency(value, table: efficiency) { e.append(frequency) }
                if name.contains("PCPU") || name.contains("MCPU"), let frequency = frequency(value, table: performance) { p.append(frequency) }
            } else if group == "Energy Model", let integer {
                let unit = unitName?(value)?.takeUnretainedValue() as String? ?? ""
                guard let watts = Self.watts(energy: integer(value, 0), unit: unit, seconds: elapsed) else { continue }
                if name.hasPrefix("CPU") { result.cpuWatts = (result.cpuWatts ?? 0) + watts }
                if name.hasPrefix("GPU") { result.gpuWatts = (result.gpuWatts ?? 0) + watts }
                if name.hasPrefix("ANE") { result.neuralWatts = (result.neuralWatts ?? 0) + watts }
                if name.hasPrefix("DRAM") || name.hasPrefix("RAM") { result.memoryWatts = (result.memoryWatts ?? 0) + watts }
            } else if group.hasPrefix("DCP"), let integer {
                let count = integer(value, 0)
                if count >= 0 { frameCount = frameCount.addingReportingOverflow(count).overflow ? frameCount : frameCount + count; hasFrames = true }
            }
        }
        result.efficiencyMHz = Self.average(e)
        result.performanceMHz = Self.average(p)
        if hasFrames { result.displayFramesPerSecond = Double(frameCount) / elapsed }
        // Recent macOS versions can expose frozen Energy Model counters without granting
        // energy access. A never-changing zero is unavailable until that channel advances.
        if (result.cpuWatts ?? 0) > 0 { liveEnergyChannels.insert("cpu") }
        if (result.gpuWatts ?? 0) > 0 { liveEnergyChannels.insert("gpu") }
        if (result.neuralWatts ?? 0) > 0 { liveEnergyChannels.insert("ane") }
        if (result.memoryWatts ?? 0) > 0 { liveEnergyChannels.insert("memory") }
        if !liveEnergyChannels.contains("cpu") { result.cpuWatts = nil }
        if !liveEnergyChannels.contains("gpu") { result.gpuWatts = nil }
        if !liveEnergyChannels.contains("ane") && !liveEnergyChannels.contains("cpu") { result.neuralWatts = nil }
        if !liveEnergyChannels.contains("memory") && !liveEnergyChannels.contains("cpu") { result.memoryWatts = nil }
        return result
    }

    private func frequency(_ channel: CFDictionary, table: [Double]) -> Double? {
        guard !table.isEmpty, let stateCount, let stateName, let residency else { return nil }
        let count = stateCount(channel)
        guard count > 0, count < 256 else { return nil }
        let states: [(String, Int64)] = (0..<count).map { index in
            (stateName(channel, index)?.takeUnretainedValue() as String? ?? "", residency(channel, index))
        }
        let active = states.filter { !["IDLE", "DOWN", "OFF"].contains($0.0.uppercased()) }
        return Self.weightedFrequency(table: table, residencies: active.map(\.1))
    }

    static func weightedFrequency(table: [Double], residencies: [Int64]) -> Double? {
        guard table.count == residencies.count, !table.isEmpty, residencies.allSatisfy({ $0 >= 0 }) else { return nil }
        let total = residencies.reduce(0.0) { $0 + Double($1) }
        guard total > 0 else { return nil }
        return zip(table, residencies).reduce(0) { $0 + $1.0 * Double($1.1) / total }
    }

    static func watts(energy: Int64, unit: String, seconds: Double) -> Double? {
        let divisor: Double
        switch unit.lowercased().trimmingCharacters(in: .whitespaces) {
        case "j": divisor = 1
        case "mj": divisor = 1e3
        case "uj", "µj": divisor = 1e6
        case "nj": divisor = 1e9
        case "pj": divisor = 1e12
        default: return nil
        }
        guard energy >= 0, seconds > 0 else { return nil }
        return Double(energy) / divisor / seconds
    }

    private static func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

    private static func frequencyTables() -> ([Double], [Double]) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
        guard service != 0 else { return ([], []) }
        defer { IOObjectRelease(service) }
        func table(_ key: String) -> [Double] {
            guard let data = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { return [] }
            let scale: Double = CPUReader.name.contains("M1") || CPUReader.name.contains("M2") || CPUReader.name.contains("M3") ? 1e6 : 1e3
            return stride(from: 0, to: data.count - data.count % 8, by: 8).compactMap { offset in
                let raw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
                let value = Double(UInt32(littleEndian: raw)) / scale
                return value > 0 && value < 10_000 ? value : nil
            }
        }
        return (table("voltage-states1-sram"), table(CPUReader.name.contains("M5") ? "voltage-states22-sram" : "voltage-states5-sram"))
    }
}


nonisolated extension Duration {
    var secondsValue: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
