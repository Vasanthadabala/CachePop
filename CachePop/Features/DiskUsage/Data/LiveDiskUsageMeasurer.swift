import Foundation

nonisolated struct LiveDiskUsageMeasurer: DiskUsageMeasuring {
    @concurrent
    func entries(in folder: URL, adding extra: [UsageEntry]) async -> [UsageEntry] {
        DiskUsageScanner.entries(in: folder, adding: extra)
    }
    func measure(_ entries: [UsageEntry], onMeasured: @escaping @Sendable (UsageEntry) async -> Void) async {
        await DiskUsageScanner.measure(entries, onMeasured: onMeasured)
    }
}
