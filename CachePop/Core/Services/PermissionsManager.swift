import AppKit
import Foundation

/// Tracks whether CachePop has Full Disk Access.
///
/// CachePop isn't sandboxed, so it can already read developer folders, run `simctl` and `brew`,
/// and clean user caches. macOS's privacy layer (TCC) still hides a few places — the Trash,
/// Safari's and some Apple apps' caches — unless the user grants Full Disk Access.
@Observable
@MainActor
final class PermissionsManager {
    static let shared = PermissionsManager()

    private(set) var hasFullDiskAccess = false

    private init() {
        refresh()
    }

    /// Re-check, e.g. when the app becomes active after the user visited System Settings.
    func refresh() {
        hasFullDiskAccess = Self.probeFullDiskAccess()
    }

    func requestFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The system TCC database and the Trash are both readable only with Full Disk Access.
    /// `isReadableFile` only checks POSIX bits, so actually try to open them.
    nonisolated static func probeFullDiskAccess() -> Bool {
        let tccDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(tccDatabase, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }

        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        return (try? FileManager.default.contentsOfDirectory(atPath: trash)) != nil
    }
}
