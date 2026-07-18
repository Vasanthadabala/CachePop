import AppKit
import Foundation

enum FileActionError: Error {
    case permissionDenied(String)
    case notFound(String)
    case unknown(Error)
}

struct FileActionResult {
    let bytesFreed: Int64
    let itemsRemoved: Int
    let errors: [FileActionError]
}

@Observable
final class FileActionService {
    static let shared = FileActionService()
    
    private init() {}
    
    /// Moves files to the macOS Trash using NSWorkspace
    func moveToTrash(paths: [String]) async -> FileActionResult {
        await processFiles(paths: paths, action: { url in
            NSWorkspace.shared.recycle([url], completionHandler: { _, error in
                if let error = error {
                    // NSWorkspace recycle completion handler doesn't throw, but reports errors
                    print("Failed to recycle \(url.path): \(error.localizedDescription)")
                }
            })
        })
    }
    
    private func processFiles(paths: [String], action: @escaping (URL) throws -> Void) async -> FileActionResult {
        var bytesFreed: Int64 = 0
        var itemsRemoved = 0
        var errors: [FileActionError] = []
        
        // Process in chunks to avoid blocking the main thread for too long
        // and to keep memory usage stable when deleting thousands of cache files.
        for path in paths {
            let url = URL(fileURLWithPath: path)
            
            // Check if file exists and get size before deletion
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                errors.append(.notFound(path))
                continue
            }
            
            do {
                let size = try calculateSize(at: url, isDirectory: isDirectory.boolValue)
                try action(url)
                
                bytesFreed += size
                itemsRemoved += 1
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError {
                    errors.append(.permissionDenied(path))
                } else {
                    errors.append(.unknown(error))
                }
            }
        }
        
        return FileActionResult(bytesFreed: bytesFreed, itemsRemoved: itemsRemoved, errors: errors)
    }
    
    private func calculateSize(at url: URL, isDirectory: Bool) throws -> Int64 {
        if !isDirectory {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        
        // It's a directory, we need to sum up contents
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
