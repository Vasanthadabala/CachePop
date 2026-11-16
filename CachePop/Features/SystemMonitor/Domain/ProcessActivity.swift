import Foundation

nonisolated struct GPUProcessUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let percent: Double
    var id: Int32 { pid }
}


nonisolated struct DriveProcessUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    let readPerSecond: Double
    let writePerSecond: Double
    var id: Int32 { pid }
}
