import Foundation

nonisolated enum CPUCoreTopology {
    static func label(_ index: Int, topology: [Int: CPUCoreKind]) -> String {
        guard let kind = topology[index] else { return "Core \(index + 1)" }
        let number = topology.filter { $0.key <= index && $0.value == kind }.count
        return "\(kind == .efficiency ? "Efficiency" : "Performance") \(number)"
    }
    static func average(_ kind: CPUCoreKind, loads: [Double], topology: [Int: CPUCoreKind]) -> Double? {
        let values = loads.enumerated().filter { topology[$0.offset] == kind }.map(\.element)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}


