import Foundation

nonisolated extension CleanupItem {
    /// Narrows operations to the scanned entries the user selected. File operations stay
    /// batched; tools that accept one target at a time get one selection per target.
    func scopedSelections(entryIDs: Set<String>, actionID: String?) -> [CleanupSelection] {
        let action = action(withID: actionID)
        guard !entries.isEmpty else {
            return entryIDs.contains(id) ? [CleanupSelection(item: self, action: action)] : []
        }
        let chosen = entries.filter { entryIDs.contains($0.id) && $0.operations[action.id] != nil }
        guard !chosen.isEmpty else { return [] }
        let operations = chosen.compactMap { $0.operations[action.id] }
        if let combined = Self.combine(operations) {
            let scopedAction = CleanupAction(id: action.id, title: action.title, operation: combined,
                                             regeneration: action.regeneration, explanation: action.explanation)
            let item = scopedItem(id: id, title: title, action: scopedAction, entries: chosen, parentID: parentID)
            return [CleanupSelection(item: item, action: scopedAction)]
        }
        return chosen.compactMap { entry in
            guard let operation = entry.operations[action.id] else { return nil }
            let scopedAction = CleanupAction(id: action.id, title: action.title, operation: operation,
                                             regeneration: action.regeneration, explanation: action.explanation)
            let item = scopedItem(id: id + "::" + entry.id, title: title + " — " + entry.title,
                                  action: scopedAction, entries: [entry], parentID: id)
            return CleanupSelection(item: item, action: scopedAction)
        }
    }

    private func scopedItem(id: String, title: String, action: CleanupAction,
                            entries: [CleanupEntry], parentID: String?) -> CleanupItem {
        CleanupItem(id: id, group: group, title: title, explanation: explanation,
                    detail: detail, sizeBytes: entries.reduce(0) { $0 + ($1.sizeBytes ?? 0) },
                    sizeIsUpperBound: sizeIsUpperBound, actions: [action], isRecommended: isRecommended,
                    warning: warning, note: note, blockedReason: blockedReason,
                    needsFullDiskAccess: needsFullDiskAccess,
                    inUseCheck: entries.count == 1 ? entries[0].inUseCheck ?? inUseCheck : inUseCheck,
                    entries: entries, parentID: parentID)
    }

    private static func combine(_ operations: [CleanupOperation]) -> CleanupOperation? {
        guard let first = operations.first else { return nil }
        if operations.count == 1 { return first }
        switch first {
        case .delete:
            var paths: [URL] = []
            for caseOperation in operations {
                guard case .delete(let urls) = caseOperation else { return nil }
                paths += urls
            }
            return .delete(paths)
        case .deleteContents:
            var paths: [URL] = []
            for caseOperation in operations {
                guard case .deleteContents(let urls) = caseOperation else { return nil }
                paths += urls
            }
            return .deleteContents(paths)
        case .moveToTrash:
            var paths: [URL] = []
            for caseOperation in operations {
                guard case .moveToTrash(let urls) = caseOperation else { return nil }
                paths += urls
            }
            return .moveToTrash(paths)
        case .command:
            return nil
        }
    }
}
