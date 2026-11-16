import Foundation

nonisolated protocol DiskUsageMeasuring: Sendable {
    func entries(in folder: URL, adding extra: [UsageEntry]) async -> [UsageEntry]
    func measure(_ entries: [UsageEntry], onMeasured: @escaping @Sendable (UsageEntry) async -> Void) async
}
