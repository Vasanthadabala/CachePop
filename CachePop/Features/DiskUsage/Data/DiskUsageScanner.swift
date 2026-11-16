import Foundation

/// Lists a folder's contents for Disk Usage. Read-only.
nonisolated enum DiskUsageScanner {
    /// Rows smaller than this are folded into one "Other items" row.
    static let minimumRowBytes = DiskUsagePolicy.minimumRowBytes

    static func entries(in folder: URL, adding extra: [UsageEntry] = []) -> [UsageEntry] {
        var seen = Set(extra.map(\.id))
        return extra + FileManager.default.children(of: folder).compactMap { url in
            guard !Task.isCancelled, seen.insert(url.path).inserted else { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            guard values?.isSymbolicLink != true else { return nil }
            return UsageEntry(url: url, isDirectory: values?.isDirectory == true && values?.isPackage != true)
        }
    }

    /// Measures every entry, at most `width` at a time, reporting each as it finishes.
    static func measure(
        _ entries: [UsageEntry],
        width: Int = 4,
        onMeasured: @escaping @Sendable (UsageEntry) async -> Void
    ) async {
        await withTaskGroup(of: UsageEntry.self) { group in
            var remaining = entries.makeIterator()
            for _ in 0..<width {
                if let entry = remaining.next() { group.addTask { measured(entry) } }
            }
            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                await onMeasured(result)
                if let entry = remaining.next() { group.addTask { measured(entry) } }
            }
        }
    }

    static func measured(_ entry: UsageEntry) -> UsageEntry {
        let size = DirectorySizer.size(of: entry.url)
        var result = entry
        result.bytes = size.bytes
        result.hasUnreadableParts = size.hasUnreadableParts
        return result
    }
}
