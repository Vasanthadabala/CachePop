import AppKit
import Foundation

nonisolated enum SystemInfoService {
    @concurrent
    static func readDisk(for url: URL) async -> DiskInfo {
        guard !Task.isCancelled else { return .empty }
        return disk(for: url)
    }

    /// Total size and free space of the volume holding the home folder. "Free" is the
    /// important-usage figure Finder shows, which counts purgeable space as available.
    static func disk(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> DiskInfo {
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey, .volumeURLKey
        ]) else {
            return .empty
        }

        return DiskInfo(
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
            volumeName: values.volumeName ?? "Drive",
            volumeURL: values.volume
        )
    }

    static func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
