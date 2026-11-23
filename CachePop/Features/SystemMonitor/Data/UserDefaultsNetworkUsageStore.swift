import Foundation

/// Stores daily byte totals only. Interface identities and IP addresses are never persisted.
@MainActor
final class UserDefaultsNetworkUsageStore: NetworkUsageStoring {
    private let defaults: UserDefaults
    private let key = "monitor.networkUsage.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> NetworkUsageHistory {
        guard let data = defaults.data(forKey: key), data.count <= 65_536,
              let value = try? PropertyListDecoder().decode(NetworkUsageHistory.self, from: data),
              value.days.count <= 63,
              value.startedAt?.timeIntervalSince1970.isFinite != false else { return NetworkUsageHistory() }
        return value
    }

    func save(_ history: NetworkUsageHistory) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}
