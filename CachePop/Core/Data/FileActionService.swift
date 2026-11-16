import AppKit
import Foundation

final class FileActionService: FileActionPerforming {
    static let shared = FileActionService()

    private init() {}

    /// Moves files to the macOS Trash.
    ///
    /// Uses `FileManager.trashItem`, which is synchronous and throws, so a failure to trash an
    /// item is actually surfaced instead of being counted as a success. The size of each item is
    /// measured before the move so `bytesFreed` reflects only what was really reclaimed.
    func moveToTrash(paths: [String], reviewed: [String: FileReviewIdentity] = [:]) async -> FileActionResult {
        await Task.detached(priority: .userInitiated) {
            var bytesFreed: Int64 = 0
            var itemsRemoved = 0
            var errors: [FileActionError] = []
            var trashed: [TrashedItem] = []

            for path in paths {
                autoreleasepool {
                    let url = URL(fileURLWithPath: path)
                    if let expected = reviewed[path], !expected.matches(url) {
                        errors.append(.changedSinceScan(path))
                        return
                    }

                    // `fileExists` follows symlinks: a link to a folder would be measured as the
                    // folder (only the link is trashed), and a dangling link reported missing.
                    let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    var isDirectory: ObjCBool = false
                    guard isSymlink || FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                        errors.append(.notFound(path))
                        return
                    }

                    // Measure before removing — afterwards the item is gone.
                    let size = isSymlink ? 0 : (try? Self.calculateSize(at: url, isDirectory: isDirectory.boolValue)) ?? 0

                    do {
                        // Size measurement can take time. Check again immediately before the move.
                        if let expected = reviewed[path], !expected.matches(url) {
                            errors.append(.changedSinceScan(path))
                            return
                        }
                        var resulting: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                        if let destination = resulting as URL? {
                            trashed.append(TrashedItem(original: url, trashed: destination))
                        }
                        bytesFreed += size
                        itemsRemoved += 1
                    } catch {
                        let nsError = error as NSError
                        if nsError.domain == NSCocoaErrorDomain,
                           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
                            errors.append(.permissionDenied(path))
                        } else {
                            errors.append(.failed(path: path, message: error.localizedDescription))
                        }
                    }
                }
            }

            return FileActionResult(bytesFreed: bytesFreed, itemsRemoved: itemsRemoved, errors: errors, trashed: trashed)
        }.value
    }

    /// Total allocated size of a file, or the recursive size of a directory.
    nonisolated static func calculateSize(at url: URL, isDirectory: Bool) throws -> Int64 {
        try Task.checkCancellation()
        if !isDirectory {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        let keySet = Set(keys)
        // Drain the enumerator's autoreleased URLs per file: an app bundle such as Xcode holds
        // hundreds of thousands of files.
        var done = false
        while !done {
            try Task.checkCancellation()
            autoreleasepool {
                guard let fileURL = enumerator.nextObject() as? URL else {
                    done = true
                    return
                }
                if let values = try? fileURL.resourceValues(forKeys: keySet), values.isRegularFile == true {
                    totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
            }
        }
        return totalSize
    }
}
