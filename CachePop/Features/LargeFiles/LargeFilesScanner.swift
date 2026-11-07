import CryptoKit
import Foundation
import Synchronization
import UniformTypeIdentifiers

/// What kind of file something is, for the Large Files filter.
nonisolated enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case videos, diskImages, archives, audio, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos:     "Videos"
        case .diskImages: "Disk images & installers"
        case .archives:   "Archives"
        case .audio:      "Audio"
        case .other:      "Other"
        }
    }

    static let diskImageExtensions: Set<String> = [
        "dmg", "iso", "img", "pkg", "mpkg", "ipsw", "sparseimage", "xip", "vmdk", "qcow2", "vdi", "raw", "toast"
    ]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz4"]

    /// Kinds by extension. The `UTType` lookup is slow, and the filters and counts in the list
    /// ask again for every file on every redraw.
    private static let kindsByExtension = Mutex<[String: FileKind]>([:])

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if let known = kindsByExtension.withLock({ $0[ext] }) { return known }
        let kind = of(extension: ext)
        kindsByExtension.withLock { $0[ext] = kind }
        return kind
    }

    private static func of(extension ext: String) -> FileKind {
        if diskImageExtensions.contains(ext) { return .diskImages }
        if archiveExtensions.contains(ext) { return .archives }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .diskImage) { return .diskImages }
        return .other
    }
}

/// How old a file must be to show, for the Large Files filter.
nonisolated enum FileAge: Int, CaseIterable, Identifiable, Sendable {
    case any = 0, threeMonths = 90, sixMonths = 180, year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .any:         "Any date"
        case .threeMonths: "Not changed in 3 months"
        case .sixMonths:   "Not changed in 6 months"
        case .year:        "Not changed in a year"
        }
    }

    func includes(_ file: FoundFile, now: Date = Date()) -> Bool {
        guard self != .any else { return true }
        guard let modified = file.modified else { return true }
        return now.timeIntervalSince(modified) >= TimeInterval(rawValue) * 86_400
    }
}

nonisolated struct FoundFile: Identifiable, Sendable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Files with identical contents. Sorted newest first, so the first is the one to keep.
nonisolated struct DuplicateSet: Identifiable, Sendable, Equatable {
    let id: String
    let files: [FoundFile]

    var fileSize: Int64 { files.first?.size ?? 0 }
    /// Space taken by every copy beyond the first.
    var extraBytes: Int64 { fileSize * Int64(max(files.count - 1, 0)) }
}

nonisolated struct LargeFilesResult: Sendable, Equatable {
    var largeFiles: [FoundFile] = []
    var duplicates: [DuplicateSet] = []
    var scannedFileCount = 0
    var unreadableCount = 0

    var largeBytes: Int64 { largeFiles.reduce(0) { $0 + $1.size } }
    var duplicateExtraBytes: Int64 { duplicates.reduce(0) { $0 + $1.extraBytes } }

    static let empty = LargeFilesResult()
}

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
        progress: @Sendable (String) -> Void = { _ in }
    ) -> LargeFilesResult {
        var result = LargeFilesResult()
        var bySize: [Int64: [FoundFile]] = [:]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]

        for root in distinctRoots(roots) {
            progress(root.path)
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

            for case let url as URL in enumerator {
                if Task.isCancelled { return result }
                guard result.scannedFileCount < fileLimit else { break }
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }

                if values.isDirectory == true {
                    if shouldSkip(url) { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true else { continue }

                result.scannedFileCount += 1
                if result.scannedFileCount.isMultiple(of: 2_000) { progress(url.deletingLastPathComponent().path) }

                let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                let file = FoundFile(url: url, size: size, modified: values.contentModificationDate)
                if size >= largeThreshold { result.largeFiles.append(file) }
                if size >= duplicateMinimumSize { bySize[Int64(values.fileSize ?? 0), default: []].append(file) }
            }
            result.unreadableCount += unreadable
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
            let byQuickHash = Dictionary(grouping: group) { quickHash($0.url) ?? "unreadable-\($0.id)" }
            for candidates in byQuickHash.values where candidates.count > 1 {
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
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = 65_536
        var hasher = SHA256()
        if let head = try? handle.read(upToCount: chunk) { hasher.update(data: head) }
        if let end = try? handle.seekToEnd(), end > UInt64(chunk) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let data = autoreleasepool { (try? handle.read(upToCount: 4 * 1_048_576)) ?? Data() }
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
