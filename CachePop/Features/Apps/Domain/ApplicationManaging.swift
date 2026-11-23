import Foundation

@MainActor
protocol ApplicationManaging {
    func scanApplications(onProgress: @escaping @MainActor @Sendable (Double) -> Void) async -> [ApplicationDetails]
    func findRelatedFiles(for app: ApplicationDetails, installedBundleIDs: Set<String>?, priority: TaskPriority) async -> [ApplicationRelatedFile]
    func isRunning(_ app: ApplicationDetails) -> Bool
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool
    func uninstall(app: ApplicationDetails, removing relatedFiles: [ApplicationRelatedFile]) async throws -> UninstallResult
}

extension ApplicationManaging {
    func scanApplications() async -> [ApplicationDetails] {
        await scanApplications(onProgress: { _ in })
    }
}
