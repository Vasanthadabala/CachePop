import Foundation

nonisolated struct GPUSample: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    var utilization: Double?
    var renderer: Double?
    var tiler: Double?
    var memoryBytes: Int64?

    static func percentage(_ number: NSNumber?) -> Double? {
        guard let value = number?.doubleValue, value.isFinite, (0...100).contains(value) else { return nil }
        return value / 100
    }
}


nonisolated enum CPUCoreKind: String, Sendable { case efficiency, performance }


nonisolated struct MountedVolume: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let format: String
    let total: Int64
    let available: Int64
    let isReadOnly: Bool
    var bsdName: String? = nil
    var driverID: String? = nil
    var isEncrypted: Bool? = nil
    var usedFraction: Double { total > 0 ? min(max(Double(total - available) / Double(total), 0), 1) : 0 }
}


nonisolated struct MonitorEnvironment: Sendable, Equatable {
    var volumes: [MountedVolume] = []
    var hasLoaded = false
    var hardware: [DriveHardware] = []
}
