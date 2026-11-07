import Foundation

nonisolated struct SizeInfo: Sendable, Equatable {
    var bytes: Int64 = 0
    var fileCount = 0
    /// Some files are hard links, so their storage may be shared with files elsewhere.
    var hasSharedFiles = false
    /// Part of the tree couldn't be read (usually a privacy-protected folder).
    var hasUnreadableParts = false

    static let zero = SizeInfo()

    static func + (lhs: SizeInfo, rhs: SizeInfo) -> SizeInfo {
        SizeInfo(
            bytes: lhs.bytes + rhs.bytes,
            fileCount: lhs.fileCount + rhs.fileCount,
            hasSharedFiles: lhs.hasSharedFiles || rhs.hasSharedFiles,
            hasUnreadableParts: lhs.hasUnreadableParts || rhs.hasUnreadableParts
        )
    }
}

/// Measures allocated size on disk, the way Finder's "on disk" figure does.
///
/// Unlike the old scanner it doesn't skip package contents (an `.xcarchive` or `.app` inside a
/// cache is real space), counts each hard-linked file once, and never follows symlinks.
nonisolated enum DirectorySizer {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .linkCountKey
    ]

    static func size(of url: URL) -> SizeInfo {
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return FileManager.default.fileExists(atPath: url.path)
                ? SizeInfo(hasUnreadableParts: true)
                : .zero
        }

        if values.isSymbolicLink == true {
            return .zero
        }

        if values.isDirectory != true {
            return SizeInfo(bytes: allocatedSize(values), fileCount: 1)
        }

        var info = SizeInfo()
        var seenInodes = Set<Inode>()
        var unreadable = false

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                unreadable = true
                return true
            }
        ) else {
            return SizeInfo(hasUnreadableParts: true)
        }

        var visited = 0
        var done = false
        while !done {
            // Every URL and resource-value dictionary the enumerator hands out is autoreleased.
            // Drain them per file, or measuring ~/Library or an Xcode install holds all of them
            // (hundreds of MB) until the measurement ends.
            autoreleasepool {
                guard let next = enumerator.nextObject() else {
                    done = true
                    return
                }
                visited += 1
                if visited.isMultiple(of: 4_000), Task.isCancelled {
                    done = true
                    return
                }

                guard let fileURL = next as? URL,
                      let fileValues = try? fileURL.resourceValues(forKeys: keys),
                      fileValues.isRegularFile == true else {
                    return
                }

                if let links = fileValues.linkCount, links > 1 {
                    info.hasSharedFiles = true
                    guard let inode = inodeKey(fileURL), seenInodes.insert(inode).inserted else { return }
                }

                info.bytes += allocatedSize(fileValues)
                info.fileCount += 1
            }
        }

        info.hasUnreadableParts = unreadable
        return info
    }

    /// Size of everything inside `url`, or zero if it doesn't exist.
    static func size(ofAll urls: [URL]) -> SizeInfo {
        urls.reduce(SizeInfo.zero) { $0 + size(of: $1) }
    }

    private static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Identifies a file's storage, for counting hard links once. Two integers rather than a
    /// formatted string: hard-link-heavy trees (pnpm, toolchains) can hold hundreds of thousands.
    nonisolated private struct Inode: Hashable {
        let device: Int64
        let number: UInt64
    }

    private static func inodeKey(_ url: URL) -> Inode? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Inode(device: Int64(info.st_dev), number: UInt64(info.st_ino))
    }
}

nonisolated extension FileManager {
    /// Immediate children of a folder, including hidden ones, or empty if unreadable.
    func children(of url: URL) -> [URL] {
        (try? contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
