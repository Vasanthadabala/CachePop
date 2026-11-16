import Foundation

nonisolated struct LiveTrashRestorer: TrashRestoring {
    func restore(_ items: [TrashedItem]) async -> RestoreOutcome {
        await PutBack.restoreInBackground(items)
    }
}
