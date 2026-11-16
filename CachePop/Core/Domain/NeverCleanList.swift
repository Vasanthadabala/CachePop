import Foundation

nonisolated struct NeverCleanList: Sendable, Equatable {
    var folders: [URL] = []
    var itemIDs: Set<String> = []

    var isEmpty: Bool { folders.isEmpty && itemIDs.isEmpty }

}
