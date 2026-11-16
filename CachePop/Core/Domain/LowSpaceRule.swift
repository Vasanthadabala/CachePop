import Foundation

/// Decides when to warn that the disk is nearly full: once when free space drops below the
/// threshold, then not again until it has recovered and dropped again, and at most once a day.
struct LowSpaceRule: Codable, Equatable {
    /// Free space must climb this much above the threshold before another alert can fire.
    static let recoveryMargin = 1.1
    static let minimumInterval: TimeInterval = 86_400

    var isArmed = true
    var lastAlert: Date?

    /// Returns true when an alert should be shown now, and updates the rule's state.
    mutating func evaluate(availableBytes: Int64, thresholdBytes: Int64, now: Date) -> Bool {
        guard thresholdBytes > 0, availableBytes >= 0 else { return false }
        if Double(availableBytes) > Double(thresholdBytes) * Self.recoveryMargin {
            isArmed = true
            return false
        }
        guard availableBytes < thresholdBytes, isArmed else { return false }
        if let lastAlert, now.timeIntervalSince(lastAlert) < Self.minimumInterval { return false }
        isArmed = false
        lastAlert = now
        return true
    }
}

/// Shows a notification. Swapped out in demo mode and tests.
@MainActor
protocol NotificationPosting {
    func requestPermission() async -> Bool
    func postLowSpace(availableBytes: Int64)
}
