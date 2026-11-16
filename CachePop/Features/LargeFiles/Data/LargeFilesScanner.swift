import CryptoKit
import Foundation
import Synchronization
import UniformTypeIdentifiers

/// What kind of file something is, for the Large Files filter.
/// Finds big files and exact duplicates in user folders. Read-only: the view model moves the
/// files the user picks to the Trash.
nonisolated enum LargeFilesScanner {
    static let largeFileThreshold: Int64 = 100 * 1_048_576
    /// Small duplicates aren't worth the hashing time or the user's attention.
    static let duplicateMinimumSize: Int64 = 1_048_576
    static let fileLimit = 300_000

    /// Build output and dependency folders: big, regenerable, and not the user's files.
    static let skippedFolderNames: Set<String> = [
        ".build", ".dart_tool", ".gradle", ".idea", ".next", ".nuxt", ".svelte-kit", ".swiftpm",
        ".venv", "build", "coverage", "deriveddata", "dist", "node_modules", "pods", "target",
        "vendor", "venv", "carthage"
    ]

    /// A folder holding one of these is a source-code project and is left alone.
    static let projectMarkers = [".git", "Package.swift", "package.json", "build.gradle", "Cargo.toml", "go.mod", "pubspec.yaml"]

    static func homeFolders(home: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func scan(
        roots: [URL],
        largeThreshold: Int64 = largeFileThreshold,
        maximumFiles: Int = fileLimit,
        progress: @Sendable (String) -> Void = { _ in }
    ) -> LargeFilesResult {
        var result = LargeFilesResult()
        var bySize: [Int64: [FoundFile]] = [:]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]

        for root in distinctRoots(roots) {
            progress(root.path)
            guard FileManager.default.fileExists(atPath: root.path) else {
                result.unreadableCount += 1
                continue
            }
            var unreadable = 0
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in
                    unreadable += 1
                    return true
                }
            ) else { continue }

            var done = false
            while !done {
                if Task.isCancelled { return result }
                autoreleasepool {
                    guard var url = enumerator.nextObject() as? URL else { done = true; return }
                    guard result.scannedFileCount < maximumFiles else {
                        result.wasLimited = true
                        done = true
                        return
                    }
                    guard let values = try? url.resourceValues(forKeys: keys) else {
                        unreadable += 1
                        return
                    }
                    if values.isDirectory == true {
                        if shouldSkip(url) { enumerator.skipDescendants() }
                        return
                    }
                    guard values.isRegularFile == true else { return }

                    result.scannedFileCount += 1
                    if result.scannedFileCount.isMultiple(of: 2_000) { progress(url.deletingLastPathComponent().path) }

                    let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    guard size >= largeThreshold || size >= duplicateMinimumSize else { return }
                    let modified = values.contentModificationDate
                    let logicalSize = Int64(values.fileSize ?? 0)
                    // Results need the path, not the enumerator's cached metadata dictionaries.
                    url.removeAllCachedResourceValues()
                    guard let identity = FileReviewIdentity.read(url) else { unreadable += 1; return }
                    let file = FoundFile(url: url, size: size, modified: modified, identity: identity)
                    if size >= largeThreshold { result.largeFiles.append(file) }
                    if size >= duplicateMinimumSize { bySize[logicalSize, default: []].append(file) }
                }
            }
            result.unreadableCount += unreadable
            if result.wasLimited { break }
        }

        result.largeFiles.sort { $0.size > $1.size }
        progress("Comparing files with the same size…")
        result.duplicates = duplicateSets(bySize.values.filter { $0.count > 1 })
        return result
    }

    /// `roots` without any that is the same folder as, or inside, another (Settings allows adding
    /// both ~/Documents and ~/Documents/Work). Walking a file twice would list it as its own
    /// duplicate, and trashing the "extra copy" would trash the only one.
    static func distinctRoots(_ roots: [URL]) -> [URL] {
        let paths = roots.map { PathSafety.canonicalPath($0) ?? $0.standardizedFileURL.path }
        var kept: [Int] = []
        // Shortest first, so a folder is kept before anything inside it.
        for index in paths.indices.sorted(by: { paths[$0].count < paths[$1].count }) {
            let path = paths[index]
            let isCovered = kept.contains { parent in
                let parentPath = paths[parent]
                return path == parentPath || path.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
            }
            if !isCovered { kept.append(index) }
        }
        return kept.sorted().map { roots[$0] }
    }

    static func shouldSkip(_ directory: URL) -> Bool {
        if skippedFolderNames.contains(directory.lastPathComponent.lowercased()) { return true }
        if directory.pathExtension == "xcodeproj" || directory.pathExtension == "xcworkspace" { return true }
        let fileManager = FileManager.default
        return projectMarkers.contains { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Same size → same first and last 64 KB → same SHA-256. Each step only reads files that
    /// still have a match, so most files are never read at all.
    static func duplicateSets(_ sameSizeGroups: [[FoundFile]]) -> [DuplicateSet] {
        var sets: [DuplicateSet] = []
        for group in sameSizeGroups {
            if Task.isCancelled { break }
            // Hard links are names for the same storage, not extra duplicate copies.
            var seenStorage = Set<FileReviewIdentity.Storage>()
            let distinct = group.filter { file in
                guard let identity = file.identity else { return true }
                return seenStorage.insert(identity.storage).inserted
            }
            let byQuickHash = Dictionary(grouping: distinct) { quickHash($0.url) ?? "unreadable-\($0.id)" }
            guard !Task.isCancelled else { return [] }
            for candidates in byQuickHash.values where candidates.count > 1 {
                guard !Task.isCancelled else { return [] }
                let byFullHash = Dictionary(grouping: candidates) { fullHash($0.url) ?? "unreadable-\($0.id)" }
                for (hash, files) in byFullHash where files.count > 1 && !hash.hasPrefix("unreadable-") {
                    let newestFirst = files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
                    sets.append(DuplicateSet(id: hash, files: newestFirst))
                }
            }
        }
        return sets.sorted { $0.extraBytes > $1.extraBytes }
    }

    static func quickHash(_ url: URL) -> String? {
        guard !Task.isCancelled, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = 65_536
        var hasher = SHA256()
        do {
            if let head = try handle.read(upToCount: chunk) { hasher.update(data: head) }
            let end = try handle.seekToEnd()
            if end > UInt64(chunk) {
                try handle.seek(toOffset: end - UInt64(chunk))
                if let tail = try handle.read(upToCount: chunk) { hasher.update(data: tail) }
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard !Task.isCancelled, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return hashContents { try handle.read(upToCount: 4 * 1_048_576) }
    }

    /// A failed read is not EOF: a partial digest must never identify two files as duplicates.
    static func hashContents(readChunk: () throws -> Data?) -> String? {
        var hasher = SHA256()
        do {
            while true {
                if Task.isCancelled { return nil }
                let data = try autoreleasepool { try readChunk() }
                guard let data, !data.isEmpty else { break }
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
