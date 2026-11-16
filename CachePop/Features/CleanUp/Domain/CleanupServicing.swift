import Foundation

nonisolated struct CleanupSelection: Sendable, Equatable {
    let item: CleanupItem
    let action: CleanupAction
}

nonisolated protocol CleanupServicing: Sendable {
    func scan(settings: CleanupSettings, onGroup: @escaping @Sendable (CleanupGroup) async -> Void) async -> CleanupScanResult
    func clean(_ selections: [CleanupSelection], neverClean: NeverCleanList,
               onProgress: @escaping @Sendable (Int, CleanupItem) async -> Void) async -> CleanupReport
}
