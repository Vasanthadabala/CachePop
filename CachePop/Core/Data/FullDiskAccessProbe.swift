import Darwin
import Foundation

nonisolated enum FullDiskAccessProbe {
    /// The system TCC database and the Trash are both readable only with Full Disk Access.
    /// `isReadableFile` only checks POSIX bits, so actually try to open them.
    static func probeFullDiskAccess() -> Bool {
        let tccDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(tccDatabase, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }

        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        return canListDirectory(trash)
    }

    /// Probe listing permission without allocating every filename in a large Trash.
    static func canListDirectory(_ path: String) -> Bool {
        guard let directory = opendir(path) else { return false }
        defer { closedir(directory) }
        errno = 0
        _ = readdir(directory)
        return errno == 0
    }
}

nonisolated struct LivePermissionChecker: PermissionChecking {
    func hasFullDiskAccess() -> Bool { FullDiskAccessProbe.probeFullDiskAccess() }
}
