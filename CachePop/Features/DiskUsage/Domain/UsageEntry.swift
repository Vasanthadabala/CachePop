import Foundation

/// One row in Disk Usage: a folder or file and how much space it takes.
nonisolated struct UsageEntry: Identifiable, Sendable, Equatable {
    let url: URL
    let isDirectory: Bool
    /// nil while it's being measured.
    var bytes: Int64?
    var hasUnreadableParts = false

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

nonisolated enum DiskUsagePolicy {
    static let minimumRowBytes: Int64 = 1_000_000
}
