import Foundation

// MARK: - Put Back

/// Moves files CachePop sent to the Trash back where they were.
nonisolated enum PutBack {
    typealias Outcome = RestoreOutcome

    /// File moves can copy across volumes. Keep the main actor free during restoration.
    @concurrent
    static func restoreInBackground(_ items: [TrashedItem]) async -> Outcome {
        restore(items)
    }

    static func restore(_ items: [TrashedItem]) -> Outcome {
        let fileManager = FileManager.default
        func exists(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.path)
                || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
        }
        var outcome = Outcome()
        for item in items {
            guard exists(item.trashed) else {
                outcome.failures.append("\(item.original.lastPathComponent) is no longer in the Trash.")
                continue
            }
            guard !exists(item.original) else {
                outcome.failures.append("Something new is already at \(item.original.lastPathComponent).")
                continue
            }
            do {
                try fileManager.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: item.trashed, to: item.original)
                outcome.restored.append(item)
                if let identity = FileReviewIdentity.read(item.original) {
                    outcome.identities[item.original.path] = identity
                }
            } catch {
                outcome.failures.append("\(item.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
