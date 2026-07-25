import SwiftUI

enum AppSortOrder: String, CaseIterable, Identifiable {
    case size
    case name
    case lastUsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size:     "Size"
        case .name:     "Name"
        case .lastUsed: "Last used"
        }
    }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case all
    case unused
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:    "All Apps"
        case .unused: "Unused"
        case .large:  "Large"
        }
    }
}

@Observable
@MainActor
final class AppManagerViewModel {
    var applications: [ApplicationDetails] = []
    var isScanning = false
    var hasScanned = false

    var selectedAppID: String?
    var relatedFiles: [ApplicationRelatedFile] = []
    var selectedRelatedFileIDs = Set<String>()
    var isLoadingRelatedFiles = false

    var searchText = ""
    var sortOrder: AppSortOrder = .size
    var filter: AppFilter = .all

    var pendingUninstall: ApplicationDetails?
    var isUninstalling = false
    var lastUninstallResult: UninstallResult?
    var errorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var relatedFilesTask: Task<Void, Never>?

    /// Apps larger than 1 GB are treated as "large" for the filter chip.
    private let largeAppThreshold: Int64 = 1_073_741_824

    var totalAppsFound: Int { applications.count }

    var totalSizeBytes: Int64 {
        applications.reduce(0) { $0 + $1.sizeBytes }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var unusedApps: [ApplicationDetails] {
        applications.filter(\.isUnused)
    }

    var unusedSizeBytes: Int64 {
        unusedApps.reduce(0) { $0 + $1.sizeBytes }
    }

    var largeApps: [ApplicationDetails] {
        applications.filter { $0.sizeBytes >= largeAppThreshold && !$0.isProtected }
    }

    var filteredApplications: [ApplicationDetails] {
        var result = applications

        switch filter {
        case .all:
            break
        case .unused:
            result = result.filter(\.isUnused)
        case .large:
            result = result.filter { $0.sizeBytes >= largeAppThreshold && !$0.isProtected }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
            }
        }

        switch sortOrder {
        case .size:
            result.sort { $0.sizeBytes > $1.sizeBytes }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed:
            result.sort {
                ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast)
            }
        }

        return result
    }

    var selectedApp: ApplicationDetails? {
        applications.first { $0.id == selectedAppID }
    }

    var selectedRelatedFiles: [ApplicationRelatedFile] {
        relatedFiles.filter { selectedRelatedFileIDs.contains($0.id) }
    }

    var selectedRelatedSizeBytes: Int64 {
        selectedRelatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Total that would be reclaimed by uninstalling: the bundle plus every ticked leftover.
    var pendingReclaimBytes: Int64 {
        (selectedApp?.sizeBytes ?? 0) + selectedRelatedSizeBytes
    }

    var formattedPendingReclaim: String {
        ByteCountFormatter.string(fromByteCount: pendingReclaimBytes, countStyle: .file)
    }

    func scanApplications() {
        guard !isScanning else { return }
        isScanning = true
        scanTask?.cancel()

        scanTask = Task {
            let apps = await AppUninstallerEngine.shared.scanApplications()
            guard !Task.isCancelled else { return }

            self.applications = apps
            self.isScanning = false
            self.hasScanned = true

            // Keep the current selection if it survived the rescan, else pick the first app.
            if let selectedAppID, apps.contains(where: { $0.id == selectedAppID }) {
                self.loadRelatedFiles(for: selectedAppID)
            } else if let first = self.filteredApplications.first {
                self.select(first)
            } else {
                self.selectedAppID = nil
                self.relatedFiles = []
            }
        }
    }

    func select(_ app: ApplicationDetails) {
        guard selectedAppID != app.id else { return }
        selectedAppID = app.id
        loadRelatedFiles(for: app.id)
    }

    private func loadRelatedFiles(for appID: String) {
        guard let app = applications.first(where: { $0.id == appID }) else { return }

        relatedFilesTask?.cancel()
        relatedFiles = []
        selectedRelatedFileIDs = []
        isLoadingRelatedFiles = true

        relatedFilesTask = Task {
            let files = await AppUninstallerEngine.shared.findRelatedFiles(for: app)
            guard !Task.isCancelled, self.selectedAppID == appID else { return }

            self.relatedFiles = files
            // Leftovers are ticked by default — removing them is the point of a clean uninstall.
            self.selectedRelatedFileIDs = Set(files.map(\.id))
            self.isLoadingRelatedFiles = false
        }
    }

    func toggleRelatedFile(_ file: ApplicationRelatedFile) {
        if selectedRelatedFileIDs.contains(file.id) {
            selectedRelatedFileIDs.remove(file.id)
        } else {
            selectedRelatedFileIDs.insert(file.id)
        }
    }

    func toggleAllRelatedFiles() {
        if selectedRelatedFileIDs.count == relatedFiles.count {
            selectedRelatedFileIDs = []
        } else {
            selectedRelatedFileIDs = Set(relatedFiles.map(\.id))
        }
    }

    func requestUninstall() {
        guard let app = selectedApp, !app.isProtected else { return }
        errorMessage = nil
        pendingUninstall = app
    }

    func cancelUninstall() {
        pendingUninstall = nil
    }

    func confirmUninstall() {
        guard let app = pendingUninstall else { return }
        pendingUninstall = nil
        isUninstalling = true
        errorMessage = nil

        Task {
            // A running app can't be cleanly trashed, so ask it to quit first.
            if app.isRunning {
                let quit = await AppUninstallerEngine.shared.quitIfRunning(app)
                guard quit else {
                    self.isUninstalling = false
                    self.errorMessage = "\(app.name) is still running and could not be quit automatically. Quit it manually, then try again."
                    return
                }
            }

            do {
                let result = try await AppUninstallerEngine.shared.uninstall(
                    app: app,
                    removing: self.selectedRelatedFiles
                )

                self.lastUninstallResult = result
                self.applications.removeAll { $0.id == app.id }
                self.selectedAppID = nil
                self.relatedFiles = []
                self.selectedRelatedFileIDs = []
                self.isUninstalling = false

                if !result.failedPaths.isEmpty {
                    self.errorMessage = "\(result.failedPaths.count) item(s) could not be moved to the Trash. Grant Full Disk Access to remove everything."
                }

                if let next = self.filteredApplications.first {
                    self.select(next)
                }
            } catch {
                self.isUninstalling = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func dismissResult() {
        lastUninstallResult = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func cancel() {
        scanTask?.cancel()
        relatedFilesTask?.cancel()
    }
}
