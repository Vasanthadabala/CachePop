import Foundation

@MainActor
protocol ApplicationManaging {
    func scanApplications() async -> [ApplicationDetails]
    func findRelatedFiles(for app: ApplicationDetails, installedBundleIDs: Set<String>?, priority: TaskPriority) async -> [ApplicationRelatedFile]
    func isRunning(_ app: ApplicationDetails) -> Bool
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool
    func uninstall(app: ApplicationDetails, removing relatedFiles: [ApplicationRelatedFile]) async throws -> UninstallResult
}
