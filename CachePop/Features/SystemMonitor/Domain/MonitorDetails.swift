import Foundation

nonisolated enum SensorGroup: String, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, drive, battery, other
    var id: String { rawValue }
    var title: String {
        switch self { case .cpu: "CPU / Chip"; case .gpu: "GPU"; case .memory: "Memory"
        case .drive: "Drive"; case .battery: "Battery"; case .other: "Other" }
    }
    static func classify(_ name: String) -> Self {
        let name = name.lowercased()
        if name.contains("battery") || name.contains("gas gauge") { return .battery }
        if name.contains("nand") || name.contains("ssd") || name.contains("drive") { return .drive }
        if name.contains("memory") || name.hasPrefix("dimm") { return .memory }
        if name.contains("gpu") || name.contains("gacc") { return .gpu }
        if name.contains("cpu") || name.contains("pacc") || name.contains("eacc") { return .cpu }
        return .other
    }
}

nonisolated struct TemperatureSensor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let group: SensorGroup
    let celsius: Double
}

nonisolated struct MonitorStatus: Identifiable, Equatable {
    enum Level: Equatable { case normal, warning, unavailable }
    let id: String
    let title: String
    let detail: String
    let level: Level

    static func checks(snapshot: SystemSnapshot, disk: DiskInfo, isHot: Bool) -> [Self] {
        var checks = [
            Self(id: "cpu", title: "CPU / Chip", detail: isHot ? "macOS reports significant thermal pressure." : "No serious thermal pressure reported by macOS.", level: isHot ? .warning : .normal),
            Self(id: "memory", title: "Memory", detail: "Pressure: \(snapshot.memory.pressure.title). Swap: \(ByteSize.memory(snapshot.memory.swapUsed)).", level: snapshot.memory.total == 0 ? .unavailable : snapshot.memory.pressure == .normal ? .normal : .warning),
            Self(id: "drive", title: "Drive", detail: disk.totalBytes == 0 ? "Storage capacity is unavailable." : "\(ByteSize.string(disk.availableBytes)) available. Capacity check; drive hardware health is not reported.", level: disk.totalBytes == 0 ? .unavailable : disk.isLow ? .warning : .normal),
            Self(id: "sensors", title: "Temperature sensors", detail: snapshot.temperatures.sensors.isEmpty ? "No detailed temperature readings available." : "\(snapshot.temperatures.sensors.count) live readings. Missing sensors are not treated as hardware faults.", level: snapshot.temperatures.sensors.isEmpty ? .unavailable : .normal),
            Self(id: "fans", title: "Fans", detail: snapshot.fans.isEmpty ? "No fans reported. Some Macs use passive cooling." : "\(snapshot.fans.count) fans reported. A stopped fan can be normal when the Mac is cool.", level: .normal),
            Self(id: "network", title: "Network", detail: "Download \(ByteSize.rate(snapshot.network.inPerSecond)) · upload \(ByteSize.rate(snapshot.network.outPerSecond)). Activity reading; connectivity is not tested.", level: .normal)
        ]
        if let battery = snapshot.battery {
            let worn = battery.health.map { $0 < 0.8 } ?? false
            checks.append(Self(id: "battery", title: "Battery", detail: battery.health.map { "Maximum capacity \(Int(($0 * 100).rounded()))%. \(worn ? "Capacity is reduced; review battery health in System Settings." : "Capacity is within the normal monitoring range.")" } ?? "Battery capacity health is unavailable.", level: battery.health == nil ? .unavailable : worn ? .warning : .normal))
        }
        return checks
    }
}

/// Only numeric monitoring fields are retained; process names and file paths are never logged.
nonisolated struct MonitorLogRecord: Sendable {
    let date: Date
    let values: [String]
    static let header = ["time", "cpu_percent", "memory_used_bytes", "memory_total_bytes", "memory_pressure", "swap_bytes", "drive_read_bytes_per_second", "drive_write_bytes_per_second", "network_download_bytes_per_second", "network_upload_bytes_per_second", "chip_celsius", "memory_celsius", "drive_celsius", "battery_celsius", "battery_percent", "battery_health_percent", "fan_rpm"]

    init(snapshot: SystemSnapshot, date: Date = Date()) {
        self.date = date
        func number(_ value: Double?) -> String {
            value.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
        }
        values = [date.ISO8601Format(), number(snapshot.cpu.total * 100), String(snapshot.memory.used), String(snapshot.memory.total), snapshot.memory.pressure.title, String(snapshot.memory.swapUsed), number(snapshot.disk.inPerSecond), number(snapshot.disk.outPerSecond), number(snapshot.network.inPerSecond), number(snapshot.network.outPerSecond), number(snapshot.temperatures.chip), number(snapshot.temperatures.memory), number(snapshot.temperatures.ssd), number(snapshot.temperatures.battery), snapshot.battery.map { String($0.percent) } ?? "", number(snapshot.battery?.health.map { $0 * 100 }), snapshot.fans.map { number($0.rpm) }.joined(separator: ";")]
    }

    static func csv(_ rows: [Self]) -> String {
        ([header] + rows.map(\.values)).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func escape(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
