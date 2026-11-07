import AppKit
import Foundation

nonisolated struct DiskInfo: Sendable, Equatable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    /// Under 10% free is where macOS starts to struggle.
    var isLow: Bool { totalBytes > 0 && usedFraction > 0.9 }

    static let empty = DiskInfo(totalBytes: 0, availableBytes: 0)
}

nonisolated enum SystemInfoService {
    /// Total size and free space of the volume holding the home folder. "Free" is the
    /// important-usage figure Finder shows, which counts purgeable space as available.
    static func disk(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskInfo {
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return .empty
        }

        return DiskInfo(
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
