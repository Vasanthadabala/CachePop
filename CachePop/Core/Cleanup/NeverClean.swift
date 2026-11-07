import Foundation

/// Folders and items the user told CachePop never to clean.
///
/// Applied twice: when a scan finishes (matching items are hidden and sizes exclude the
/// protected folders) and again during the clean itself, so a folder added to the list
/// between scan and clean is still left alone.
nonisolated struct NeverCleanList: Sendable, Equatable {
    var folders: [URL] = []
    var itemIDs: Set<String> = []

    var isEmpty: Bool { folders.isEmpty && itemIDs.isEmpty }

    private var folderKeys: [String] { folders.map(Self.key) }

    /// True when `url` is one of the folders, or inside one.
    func protects(_ url: URL) -> Bool {
        // Called for every file a clean removes; skip the `realpath` when there's nothing to match.
        guard !folders.isEmpty else { return false }
        let target = Self.key(url)
        return folderKeys.contains { target == $0 || target.hasPrefix($0 + "/") }
    }

    /// Listed folders strictly inside `url`.
    func protectedFolders(inside url: URL) -> [URL] {
        guard !folders.isEmpty else { return [] }
        let parent = Self.key(url)
        return zip(folders, folderKeys).filter { $0.1.hasPrefix(parent + "/") }.map(\.0)
    }

    /// Lowercased canonical path. Follows symlinks in the parent but not the last component,
    /// like `PathSafety`, and still works for paths that no longer exist.
    static func key(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        let parent = PathSafety.canonicalPath(standardized.deletingLastPathComponent())
            ?? standardized.deletingLastPathComponent().path
        let path = parent.hasSuffix("/") ? parent + name : parent + "/" + name
        return path.lowercased()
    }

    // MARK: Scan results

    /// Hides listed items, and takes listed folders out of every item that touches them.
    func apply(to group: CleanupGroup) -> CleanupGroup {
        guard !isEmpty else { return group }
        var kept: [CleanupItem] = []
        var hidden = 0

        for item in group.items {
            if itemIDs.contains(item.id) {
                hidden += 1
                continue
            }
            guard !folders.isEmpty else {
                kept.append(item)
                continue
            }
            switch adjusted(item) {
            case .unchanged: kept.append(item)
            case .changed(let updated): kept.append(updated)
            case .removed: hidden += 1
            }
        }

        var result = group
        result.items = kept
        if hidden > 0 {
            result.notes.append("\(hidden) \(hidden == 1 ? "item is" : "items are") hidden by your Never Clean list in Settings.")
        }
        return result
    }

    private enum Adjustment {
        case unchanged
        case changed(CleanupItem)
        case removed
    }

    private func adjusted(_ item: CleanupItem) -> Adjustment {
        var excludedBytes: Int64 = 0
        var touched = false
        var actions: [CleanupAction] = []

        for action in item.actions {
            var operation = action.operation
            switch action.operation {
            case .delete(let urls):
                let kept = urls.filter { !protects($0) }
                if action.id == item.defaultAction.id {
                    excludedBytes += DirectorySizer.size(ofAll: urls.filter(protects)).bytes
                    excludedBytes += kept.flatMap(protectedFolders(inside:)).reduce(0) { $0 + DirectorySizer.size(of: $1).bytes }
                }
                touched = touched || kept.count != urls.count || kept.contains { !protectedFolders(inside: $0).isEmpty }
                operation = .delete(kept)
            case .deleteContents(let folders):
                let kept = folders.filter { !protects($0) }
                if action.id == item.defaultAction.id {
                    excludedBytes += DirectorySizer.size(ofAll: folders.filter(protects)).bytes
                    excludedBytes += kept.flatMap(protectedFolders(inside:)).reduce(0) { $0 + DirectorySizer.size(of: $1).bytes }
                }
                touched = touched || kept.count != folders.count || kept.contains { !protectedFolders(inside: $0).isEmpty }
                operation = .deleteContents(kept)
            case .moveToTrash(let urls):
                // A folder can't be half moved to the Trash, so one holding a listed folder stays.
                let kept = urls.filter { !protects($0) && protectedFolders(inside: $0).isEmpty }
                if action.id == item.defaultAction.id {
                    excludedBytes += DirectorySizer.size(ofAll: urls.filter { !kept.contains($0) }).bytes
                }
                touched = touched || kept.count != urls.count
                operation = .moveToTrash(kept)
            case .command:
                break
            }
            actions.append(CleanupAction(id: action.id, title: action.title, operation: operation,
                                         regeneration: action.regeneration, explanation: action.explanation))
        }

        guard touched else { return .unchanged }

        let remainingBytes = max(item.sizeBytes - excludedBytes, 0)
        let defaultIsEmpty: Bool = {
            switch actions[0].operation {
            case .delete(let urls), .deleteContents(let urls), .moveToTrash(let urls): urls.isEmpty
            case .command: false
            }
        }()
        if defaultIsEmpty || remainingBytes == 0 { return .removed }

        var updated = CleanupItem(
            id: item.id, group: item.group, title: item.title, explanation: item.explanation,
            detail: item.detail, sizeBytes: remainingBytes, sizeIsUpperBound: item.sizeIsUpperBound,
            actions: actions, isRecommended: item.isRecommended, warning: item.warning, note: item.note,
            blockedReason: item.blockedReason, needsFullDiskAccess: item.needsFullDiskAccess,
            inUseCheck: item.inUseCheck
        )
        let skipping = "Folders on your Never Clean list are left out."
        updated.note = updated.note.map { "\($0) \(skipping)" } ?? skipping
        return .changed(updated)
    }
}

// MARK: - Put Back

/// Moves files CachePop sent to the Trash back where they were.
nonisolated enum PutBack {
    nonisolated struct Outcome: Sendable, Equatable {
        var restored: [TrashedItem] = []
        var failures: [String] = []
    }

    static func restore(_ items: [TrashedItem]) -> Outcome {
        let fileManager = FileManager.default
        var outcome = Outcome()
        for item in items {
            guard fileManager.fileExists(atPath: item.trashed.path) else {
                outcome.failures.append("\(item.original.lastPathComponent) is no longer in the Trash.")
                continue
            }
            guard !fileManager.fileExists(atPath: item.original.path) else {
                outcome.failures.append("Something new is already at \(item.original.lastPathComponent).")
                continue
            }
            do {
                try fileManager.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: item.trashed, to: item.original)
                outcome.restored.append(item)
            } catch {
                outcome.failures.append("\(item.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
