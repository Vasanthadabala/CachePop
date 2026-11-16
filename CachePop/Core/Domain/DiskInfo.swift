import Foundation

nonisolated struct DiskInfo: Sendable, Equatable {
    let totalBytes: Int64
    let availableBytes: Int64
    var volumeName: String = "Drive"
    var volumeURL: URL?

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    /// Under 10% free is where macOS starts to struggle.
    var isLow: Bool { totalBytes > 0 && usedFraction > 0.9 }

    static let empty = DiskInfo(totalBytes: 0, availableBytes: 0)
}
