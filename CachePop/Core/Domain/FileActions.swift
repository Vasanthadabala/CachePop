import Foundation

nonisolated enum FileActionError: Error, Sendable {
    case permissionDenied(String)
    case notFound(String)
    case changedSinceScan(String)
    case failed(path: String, message: String)

    var path: String {
        switch self {
        case .permissionDenied(let path), .notFound(let path), .changedSinceScan(let path), .failed(let path, _):
            path
        }
    }

    var changedSinceScan: Bool {
        if case .changedSinceScan = self { return true }
        return false
    }
}

nonisolated struct FileActionResult: Sendable {
    let bytesFreed: Int64
    let itemsRemoved: Int
    let errors: [FileActionError]
    /// Where each moved item landed in the Trash, for Put Back.
    var trashed: [TrashedItem] = []

    var hasErrors: Bool { !errors.isEmpty }
}


nonisolated struct RestoreOutcome: Sendable, Equatable {
    var restored: [TrashedItem] = []
    var failures: [String] = []
    var identities: [String: FileReviewIdentity] = [:]
}

@MainActor
protocol FileActionPerforming {
    func moveToTrash(paths: [String], reviewed: [String: FileReviewIdentity]) async -> FileActionResult
}

nonisolated protocol TrashRestoring: Sendable {
    func restore(_ items: [TrashedItem]) async -> RestoreOutcome
}
