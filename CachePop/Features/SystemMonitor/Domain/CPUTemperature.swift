import Foundation

/// CPU-specific SMC sensors. PMU die sensors measure other parts of the SoC and must not be
/// averaged into the CPU reading. Key families differ between Apple silicon generations.
/// Sensor identities cross-checked against https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift.
nonisolated enum CPUTemperature {
    struct Sensor: Equatable, Sendable {
        let key: String
        let name: String
        var isPackage = false
    }

    struct Reading: Equatable, Sendable {
        let average: Double
        let maximum: Double
        let sensors: [TemperatureSensor]
    }

    /// Discover once using the SMC key inventory already needed by the memory reader.
    static func sensors(chipName: String, availableKeys: [String]) -> [Sensor] {
        let available = Set(availableKeys)
        let generation = chipName.split(separator: " ").first { $0.first == "M" }.flatMap { Int($0.dropFirst()) }
        let efficiency: [String]
        let performance: [String]
        switch generation {
        case 1:
            efficiency = ["Tp09", "Tp0T"]
            performance = ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case 2:
            efficiency = ["Tp1h", "Tp1t", "Tp1p", "Tp1l"]
            performance = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case 3:
            efficiency = ["Te05", "Te0L", "Te0P", "Te0S"]
            performance = ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case 4:
            efficiency = ["Te05", "Te09", "Te0H", "Te0S"]
            performance = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case 5:
            efficiency = []
            performance = ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        default:
            // Unknown Apple silicon must not inherit a different chip's sensor map.
            guard !chipName.hasPrefix("Apple") else { return [] }
            let package = ["TC0D", "TC0E", "TC0F", "TCAD"].map { Sensor(key: $0, name: "CPU die (\($0))", isPackage: true) }
            let cores = availableKeys.sorted().filter { key in
                let bytes = Array(key.utf8)
                return bytes.count == 4 && key.hasPrefix("TC") && "0123456789ABCDEFabcdef".utf8.contains(bytes[2])
                    && (bytes[3] == 67 || bytes[3] == 99)
            }.map { Sensor(key: $0, name: "CPU core (\($0))") }
            return (package + cores).filter { available.contains($0.key) }
        }
        let e = efficiency.enumerated().map { Sensor(key: $0.element, name: "CPU efficiency sensor \($0.offset + 1)") }
        let p = performance.enumerated().map { Sensor(key: $0.element, name: "CPU performance sensor \($0.offset + 1)") }
        return (e + p).filter { available.contains($0.key) }
    }

    /// Parked/offline cores may return zero or tiny placeholders. Never clamp those into a
    /// plausible-looking temperature or keep an old reading when the current value is invalid.
    static func read(_ sensors: [Sensor], value: (String) -> Double?) -> Reading? {
        let valid = sensors.compactMap { descriptor -> (Sensor, Double)? in
            guard let reading = value(descriptor.key), reading.isFinite, (10...120).contains(reading) else { return nil }
            return (descriptor, reading)
        }
        guard !valid.isEmpty else { return nil }
        let average = valid.first { $0.0.isPackage }?.1 ?? valid.map(\.1).reduce(0, +) / Double(valid.count)
        return Reading(average: average, maximum: valid.map(\.1).max()!, sensors: valid.map { descriptor, reading in
            TemperatureSensor(id: "smc.\(descriptor.key)", name: descriptor.name, group: .cpu, celsius: reading)
        })
    }
}
