import Foundation

nonisolated struct ProcessorIdentity: Sendable {
    let name: String
    let performanceCores: Int
    let efficiencyCores: Int
    let topology: [Int: CPUCoreKind]
}
