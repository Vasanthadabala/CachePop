import Foundation

/// A simulator as `simctl list devices -j` reports it.
nonisolated struct SimulatorDevice: Sendable, Equatable, Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    let dataPath: String?
    let dataPathSize: Int64?
    let lastUsedAt: String?

    /// Filled in from the dictionary key the device was listed under.
    var runtimeIdentifier = ""

    var isBooted: Bool { state.caseInsensitiveCompare("Shutdown") != .orderedSame }
    var available: Bool { isAvailable ?? true }

    private enum CodingKeys: String, CodingKey {
        case udid, name, state, isAvailable, dataPath, dataPathSize, lastUsedAt
    }
}

/// A downloadable simulator runtime as `simctl runtime list -j` reports it.
nonisolated struct SimulatorRuntimeImage: Sendable, Equatable, Decodable {
    let identifier: String
    let runtimeIdentifier: String?
    let version: String?
    let build: String?
    let sizeBytes: Int64?
    let deletable: Bool?
    let lastUsedAt: String?
}

nonisolated enum SimulatorDeviceSet: String, Sendable {
    case standard, testing, previews
    var arguments: [String] { self == .standard ? [] : ["--set", rawValue] }
}
