import Foundation

/// A small, minute-resolution history; no process identities or other telemetry is stored.
@MainActor
final class UserDefaultsBatteryHistoryStore: BatteryChargeHistoryStoring {
    private let defaults: UserDefaults
    private let key = "monitor.batteryChargeHistory.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [BatteryChargeReading] {
        guard let data = defaults.data(forKey: key), data.count <= 262_144,
              let values = try? PropertyListDecoder().decode([BatteryChargeReading].self, from: data) else { return [] }
        return Array(values.suffix(1_560))
    }

    func save(_ readings: [BatteryChargeReading]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Array(readings.suffix(1_560))) else { return }
        defaults.set(data, forKey: key)
    }
}
