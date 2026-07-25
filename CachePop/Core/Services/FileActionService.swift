import AppKit
import Foundation

enum FileActionError: Error {
    case permissionDenied(String)
    case notFound(String)
    case unknown(Error)

    var path: String {
        switch self {
        case .permissionDenied(let path), .notFound(let path):
            path
        case .unknown:
            ""
        }
    }
}

struct FileActionResult {
    let bytesFreed: Int64
    let itemsRemoved: Int
    let errors: [FileActionError]

    var hasErrors: Bool { !errors.isEmpty }

    var permissionDeniedCount: Int {
        errors.filter {
            if case .permissionDenied = $0 { return true }
            return false
        }.count
    }

    static let empty = FileActionResult(bytesFreed: 0, itemsRemoved: 0, errors: [])
}

@Observable
final class FileActionService {
    static let shared = FileActionService()

    private init() {}

    /// Moves files to the macOS Trash.
    ///
    /// Uses `FileManager.trashItem`, which is synchronous and throws, so a failure to trash an
    /// item is actually surfaced instead of being counted as a success. The size of each item is
    /// measured before the move so `bytesFreed` reflects only what was really reclaimed.
    func moveToTrash(paths: [String]) async -> FileActionResult {
        await Task.detached(priority: .userInitiated) {
            var bytesFreed: Int64 = 0
            var itemsRemoved = 0
            var errors: [FileActionError] = []

            for path in paths {
                autoreleasepool {
                    let url = URL(fileURLWithPath: path)

                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                        errors.append(.notFound(path))
                        return
                    }

                    // Measure before removing — afterwards the item is gone.
                    let size = (try? Self.calculateSize(at: url, isDirectory: isDirectory.boolValue)) ?? 0

                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        bytesFreed += size
                        itemsRemoved += 1
                    } catch {
                        let nsError = error as NSError
                        if nsError.domain == NSCocoaErrorDomain,
                           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
                            errors.append(.permissionDenied(path))
                        } else {
                            errors.append(.unknown(error))
                        }
                    }
                }
            }

            return FileActionResult(bytesFreed: bytesFreed, itemsRemoved: itemsRemoved, errors: errors)
        }.value
    }

    /// Total allocated size of a file, or the recursive size of a directory.
    nonisolated static func calculateSize(at url: URL, isDirectory: Bool) throws -> Int64 {
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
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return totalSize
    }
}
