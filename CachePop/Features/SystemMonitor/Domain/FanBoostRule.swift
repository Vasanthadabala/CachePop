import Foundation

nonisolated struct FanBoostRule: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, CaseIterable, Identifiable, Sendable {
        case cpu, gpu, memory, drive, battery, hottest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cpu: "CPU / chip"
            case .gpu: "GPU"
            case .memory: "Memory"
            case .drive: "Drive"
            case .battery: "Battery"
            case .hottest: "Hottest sensor"
            }
        }
        func reading(_ sample: TemperatureSample) -> Double? {
            switch self {
            case .cpu: sample.chipMax ?? sample.chip
            case .gpu: sample.sensors.filter { $0.group == .gpu }.map(\.celsius).max()
            case .memory: sample.memory
            case .drive: sample.ssd
            case .battery: sample.battery
            case .hottest: (sample.sensors.map(\.celsius) + [sample.chipMax, sample.chip, sample.memory, sample.ssd, sample.battery].compactMap { $0 }).max()
            }
        }
    }

    var id = UUID()
    var isEnabled = true
    var source: Source = .cpu
    var threshold: Double = 70
    var percent: Double = 75

    static let defaults = [FanBoostRule(threshold: 70, percent: 75), FanBoostRule(threshold: 80, percent: 100)]
}

/// The strongest matching rule wins. A 3°C release margin avoids switching back and forth.
nonisolated struct FanBoostEvaluation: Equatable {
    let active: Set<UUID>
    let percent: Double?

    static func evaluate(rules: [FanBoostRule], temperatures: TemperatureSample,
                         previous: Set<UUID>) -> Self {
        var active: Set<UUID> = []
        var percentages: [Double] = []
        for rule in rules where rule.isEnabled && rule.threshold.isFinite && rule.percent.isFinite {
            guard let reading = rule.source.reading(temperatures), reading.isFinite else { continue }
            let threshold = min(max(rule.threshold, 30), 90)
            if reading >= threshold || (previous.contains(rule.id) && reading > threshold - 3) {
                active.insert(rule.id)
                percentages.append(min(max(rule.percent, 50), 100))
            }
        }
        return Self(active: active, percent: percentages.max())
    }
}
