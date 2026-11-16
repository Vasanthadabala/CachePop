import Foundation

nonisolated enum ElectricalSensors {
    static func gpuKeys(chipName: String, available: Set<String>) -> [String] {
        let generation = chipName.split(separator: " ").first { $0.first == "M" }.flatMap { Int($0.dropFirst()) }
        let keys: [String]
        switch generation {
        case 1: keys = ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
        case 2: keys = ["Tg0f", "Tg0j"]
        case 3: keys = ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        case 4: keys = ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
        case 5: keys = ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]
        default: keys = ["TG0D", "TGDD"]
        }
        return keys.filter { available.contains($0) }
    }
    struct Descriptor {
        let key: String
        let name: String
        let kind: ElectricalSensor.Kind
    }
    static let known = [
        Descriptor(key: "PSTR", name: "System total", kind: .power),
        Descriptor(key: "PPBR", name: "Battery", kind: .power),
        Descriptor(key: "PDTR", name: "Power adapter", kind: .power),
        Descriptor(key: "VD0R", name: "DC input", kind: .voltage),
        Descriptor(key: "VP0R", name: "12 V rail", kind: .voltage),
        Descriptor(key: "ID0R", name: "DC input", kind: .current)
    ]
    static func read(keys: Set<String>, value: (String) -> Double?) -> [ElectricalSensor] {
        known.compactMap { item in
            guard keys.contains(item.key), let reading = value(item.key), reading.isFinite,
                  abs(reading) <= (item.kind == .power ? 1_000 : item.kind == .voltage ? 100 : 50) else { return nil }
            return ElectricalSensor(id: item.key, name: item.name, kind: item.kind, value: reading)
        }
    }
}
