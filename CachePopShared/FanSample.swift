import Foundation

/// One fan: its current speed and the range macOS allows.
nonisolated struct FanSample: Sendable, Equatable, Identifiable {
    let index: Int
    var rpm: Double
    var minimum: Double
    var maximum: Double

    var id: Int { index }
    var fraction: Double {
        maximum > minimum ? min(max((rpm - minimum) / (maximum - minimum), 0), 1) : 0
    }
}
