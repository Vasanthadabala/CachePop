import AppKit
import Foundation
import IOKit
import IOKit.ps

nonisolated struct BatteryInfo: Sendable {
    let isPresent: Bool
    let currentCharge: Int
    let cycleCount: Int
    /// Maximum capacity as a percentage of the battery's original design capacity.
    let healthPercent: Int
    let isCharging: Bool

    static let absent = BatteryInfo(
        isPresent: false,
        currentCharge: 0,
        cycleCount: 0,
        healthPercent: 0,
        isCharging: false
    )

    /// Apple considers a battery consumed below ~80% of design capacity.
    var needsAttention: Bool { isPresent && healthPercent > 0 && healthPercent < 80 }

    var healthLabel: String {
        guard isPresent, healthPercent > 0 else { return "Not available" }
        switch healthPercent {
        case 90...:  return "Excellent"
        case 80..<90: return "Good"
        case 60..<80: return "Fair"
        default:      return "Service recommended"
        }
    }
}

nonisolated struct DiskInfo: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Under 10% free is where macOS starts to struggle.
    var isLow: Bool { totalBytes > 0 && usedFraction > 0.9 }

    static let empty = DiskInfo(totalBytes: 0, availableBytes: 0)
}

nonisolated struct MemoryInfo: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .memory)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .memory)
    }

    var isUnderPressure: Bool { usedFraction > 0.85 }

    static let empty = MemoryInfo(totalBytes: 0, usedBytes: 0)
}

nonisolated struct SystemSnapshot: Sendable {
    var battery: BatteryInfo = .absent
    var disk: DiskInfo = .empty
    var memory: MemoryInfo = .empty
    var uptimeSeconds: TimeInterval = 0
    var osVersion: String = ""
    var modelName: String = ""

    var daysSinceRestart: Int {
        Int(uptimeSeconds / 86_400)
    }

    var uptimeText: String {
        let days = daysSinceRestart
        if days >= 1 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        let hours = Int(uptimeSeconds / 3_600)
        if hours >= 1 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        let minutes = max(Int(uptimeSeconds / 60), 1)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// A long uptime is a common cause of sluggishness.
    var needsRestart: Bool { daysSinceRestart >= 7 }

    static let empty = SystemSnapshot()
}

nonisolated enum SystemInfoService {
    static func snapshot() async -> SystemSnapshot {
        await Task.detached(priority: .utility) {
            var result = SystemSnapshot()
            result.battery = readBattery()
            result.disk = readDisk()
            result.memory = readMemory()
            result.uptimeSeconds = ProcessInfo.processInfo.systemUptime
            result.osVersion = readOSVersion()
            result.modelName = readModelName()
            return result
        }.value
    }

    // MARK: - Battery

    /// Reads the internal battery from the IORegistry. `AppleSmartBattery` exposes the raw
    /// design/max capacity pair needed for a real health percentage — the IOPowerSources API
    /// only reports current charge.
    private nonisolated static func readBattery() -> BatteryInfo {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)

        guard service != IO_OBJECT_NULL else {
            return .absent
        }

        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return .absent
        }

        let cycleCount = dict["CycleCount"] as? Int ?? 0
        let isCharging = dict["IsCharging"] as? Bool ?? false
        let currentCapacity = dict["CurrentCapacity"] as? Int ?? 0

        // Apple silicon reports raw mAh values; some Macs expose a percentage directly.
        let designCapacity = dict["DesignCapacity"] as? Int ?? 0
        let maxCapacity = dict["AppleRawMaxCapacity"] as? Int
            ?? dict["MaxCapacity"] as? Int
            ?? 0

        var healthPercent = 0
        if designCapacity > 0, maxCapacity > 0 {
            healthPercent = Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
            // Guard against firmware reporting MaxCapacity as a 0-100 percentage already.
            if healthPercent > 100, maxCapacity <= 100 {
                healthPercent = maxCapacity
            }
            healthPercent = min(healthPercent, 100)
        }

        var chargePercent = 0
        if let raw = dict["CurrentCapacity"] as? Int, let max = dict["MaxCapacity"] as? Int, max > 0 {
            chargePercent = Int((Double(raw) / Double(max) * 100).rounded())
        } else {
            chargePercent = currentCapacity
        }

        return BatteryInfo(
            isPresent: true,
            currentCharge: min(chargePercent, 100),
            cycleCount: cycleCount,
            healthPercent: healthPercent,
            isCharging: isCharging
        )
    }

    // MARK: - Disk

    private nonisolated static func readDisk() -> DiskInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return .empty
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0

        return DiskInfo(totalBytes: total, availableBytes: Int64(available))
    }

    // MARK: - Memory

    private nonisolated static func readMemory() -> MemoryInfo {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryInfo(totalBytes: total, usedBytes: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        // "Used" here mirrors Activity Monitor's memory-pressure view: resident app memory
        // plus wired and compressed pages. Cached/free pages are available for reuse.
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return MemoryInfo(totalBytes: total, usedBytes: active + wired + compressed)
    }

    // MARK: - Model

    private nonisolated static func readOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            text += ".\(version.patchVersion)"
        }
        return text
    }

    /// Returns the hardware identifier (e.g. "Mac16,12"). macOS exposes no public API for the
    /// marketing name, so this is only used for diagnostics — the UI shows the OS version instead.
    private nonisolated static func readModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let identifier = String(cString: buffer)
        return identifier.isEmpty ? "Mac" : identifier
    }

    static func openStorageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
