import Foundation

nonisolated struct ElectricalSensor: Identifiable, Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable { case power = "Power", voltage = "Voltage", current = "Current" }
    let id: String
    let name: String
    let kind: Kind
    let value: Double
    var unit: String { switch kind { case .power: "W"; case .voltage: "V"; case .current: "A" } }
    var formatted: String { String(format: kind == .power ? "%.1f %@" : "%.2f %@", value, unit) }
}
