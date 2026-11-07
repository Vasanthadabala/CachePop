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
        case .lastUsed: "Last Used"
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
        case .all:    "All"
        case .unused: "Unused"
        case .large:  "Large"
        }
    }
}

@Observable
@MainActor
final class AppsViewModel {
    private(set) var applications: [ApplicationDetails] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false

    var selectedAppID: String? {
        didSet {
            if let selectedAppID, selectedAppID != oldValue { loadRelatedFiles(for: selectedAppID) }
        }
    }
    private(set) var relatedFiles: [ApplicationRelatedFile] = []
    var selectedRelatedFileIDs = Set<String>()
    private(set) var isLoadingRelatedFiles = false
    /// True while the Library files of every app are being measured after a scan.
    private(set) var isMeasuringLibraries = false
    /// Library files found per app, so selecting an app doesn't search again.
    private var relatedFilesByApp: [String: [ApplicationRelatedFile]] = [:]
    /// Identifiers of every app macOS has in the usual folders, their subfolders and /System,
    /// including ones this list doesn't show, so leftovers never include their files.
    @ObservationIgnored private var catalogBundleIDs: Set<String> = []

    var sortOrder: AppSortOrder = .size
    var filter: AppFilter = .all

    var isConfirming = false
    private(set) var isUninstalling = false
    var lastUninstallResult: UninstallResult?
    var errorMessage: String?

    var onSpaceChanged: () -> Void = {}

    private var scanTask: Task<Void, Never>?
    private var measureTask: Task<Void, Never>?
    private var relatedFilesTask: Task<Void, Never>?

    /// Apps larger than 1 GB count as "large".
    private let largeAppThreshold: Int64 = 1_073_741_824

    /// Every app plus its Library files, as far as measured.
    var totalSizeBytes: Int64 { applications.reduce(0) { $0 + $1.totalSizeBytes } }

    var filteredApplications: [ApplicationDetails] {
        var result = applications

        switch filter {
        case .all: break
        case .unused: result = result.filter(\.isUnused)
        case .large: result = result.filter { $0.totalSizeBytes >= largeAppThreshold && !$0.isProtected }
        }

        switch sortOrder {
        case .size: result.sort { $0.totalSizeBytes > $1.totalSizeBytes }
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed: result.sort { ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast) }
        }
        return result
    }

    var selectedApp: ApplicationDetails? {
        applications.first { $0.id == selectedAppID }
    }

    var selectedRelatedFiles: [ApplicationRelatedFile] {
        relatedFiles.filter { selectedRelatedFileIDs.contains($0.id) }
    }

    var relatedBytes: Int64 { relatedFiles.reduce(0) { $0 + $1.sizeBytes } }

    /// The bundle plus every ticked leftover.
    var pendingReclaimBytes: Int64 {
        (selectedApp?.sizeBytes ?? 0) + selectedRelatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        scan()
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanTask?.cancel()

        scanTask = Task {
            let catalog = Task.detached(priority: .userInitiated) { LiveAppCatalog().installedBundleIDs() }
            let scanned = await AppUninstallerEngine.shared.scanApplications()
            let catalogIDs = await catalog.value
            guard !Task.isCancelled else { return }
            // An app uninstalled while this scan ran is in the Trash already.
            let apps = scanned.filter { FileManager.default.fileExists(atPath: $0.path) }
            catalogBundleIDs = catalogIDs
            applications = apps
            relatedFilesByApp = [:]
            isScanning = false
            hasScanned = true

            if let selectedAppID, apps.contains(where: { $0.id == selectedAppID }) {
                loadRelatedFiles(for: selectedAppID)
            } else {
                selectedAppID = filteredApplications.first?.id
            }
            measureLibraries(of: apps)
        }
    }

    /// Measures each app's Library files in the background so the list can show full sizes.
    /// It runs below the window's priority, and results land about once a second without
    /// animation, so the list stays responsive and doesn't keep reshuffling while you use it.
    private func measureLibraries(of apps: [ApplicationDetails]) {
        measureTask?.cancel()
        isMeasuringLibraries = true
        let installed = installedBundleIDs
        measureTask = Task {
            let clock = ContinuousClock()
            var lastUpdate = clock.now
            var batch: [String: [ApplicationRelatedFile]] = [:]
            for app in apps {
                if Task.isCancelled { return }
                guard relatedFilesByApp[app.id] == nil else { continue }
                let files = await AppUninstallerEngine.shared.findRelatedFiles(
                    for: app, installedBundleIDs: installed, priority: .utility
                )
                // A rescan started meanwhile: this was found against the old list of apps, and
                // the new pass measures again.
                if Task.isCancelled { return }
                batch[app.id] = files
                if clock.now - lastUpdate >= .seconds(1) {
                    record(batch)
                    batch = [:]
                    lastUpdate = clock.now
                }
            }
            if !batch.isEmpty { record(batch) }
            isMeasuringLibraries = false
        }
    }

    /// Every installed app's identifier, so one app's leftovers never include another's files.
    private var installedBundleIDs: Set<String> {
        Set(applications.map { $0.bundleIdentifier.lowercased() }.filter { !$0.isEmpty }).union(catalogBundleIDs)
    }

    /// Another listed copy of the app (Xcode and Xcode-beta share an identifier), or an app of
    /// the same name, uses the same Library files.
    private func hasAnotherCopy(_ app: ApplicationDetails) -> Bool {
        let id = app.bundleIdentifier.lowercased()
        let name = app.name.lowercased()
        return applications.contains { other in
            other.id != app.id
                && ((!id.isEmpty && other.bundleIdentifier.lowercased() == id) || other.name.lowercased() == name)
        }
    }

    /// The selected app's Library files are shared with another copy, so they start unticked.
    var selectedAppHasAnotherCopy: Bool {
        selectedApp.map(hasAnotherCopy) ?? false
    }

    /// Leftovers are ticked by default — removing them is the point of a clean uninstall —
    /// unless another copy of the app still uses them.
    private func defaultSelection(_ files: [ApplicationRelatedFile], for app: ApplicationDetails) -> Set<String> {
        hasAnotherCopy(app) ? [] : Set(files.map(\.id))
    }

    /// Stores found Library files and the app's Library size.
    private func record(_ filesByApp: [String: [ApplicationRelatedFile]]) {
        for (appID, files) in filesByApp {
            relatedFilesByApp[appID] = files
            if let index = applications.firstIndex(where: { $0.id == appID }) {
                applications[index].librarySizeBytes = files.reduce(0) { $0 + $1.sizeBytes }
            }
        }
    }

    private func loadRelatedFiles(for appID: String) {
        guard let app = applications.first(where: { $0.id == appID }) else { return }

        relatedFilesTask?.cancel()

        // Already measured in the background: show it straight away.
        if let cached = relatedFilesByApp[appID] {
            relatedFiles = cached
            selectedRelatedFileIDs = defaultSelection(cached, for: app)
            isLoadingRelatedFiles = false
            return
        }

        relatedFiles = []
        selectedRelatedFileIDs = []
        isLoadingRelatedFiles = true

        relatedFilesTask = Task {
            let files = await AppUninstallerEngine.shared.findRelatedFiles(for: app, installedBundleIDs: installedBundleIDs)
            guard !Task.isCancelled else { return }
            record([appID: files])
            guard selectedAppID == appID else { return }
            relatedFiles = files
            selectedRelatedFileIDs = defaultSelection(files, for: app)
            isLoadingRelatedFiles = false
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
        selectedRelatedFileIDs = selectedRelatedFileIDs.count == relatedFiles.count ? [] : Set(relatedFiles.map(\.id))
    }

    func requestUninstall() {
        guard let app = selectedApp, !app.isProtected else { return }
        errorMessage = nil
        isConfirming = true
    }

    func confirmUninstall() {
        guard let app = selectedApp, !app.isProtected else { return }
        isConfirming = false
        isUninstalling = true
        errorMessage = nil
        let leftovers = selectedRelatedFiles

        Task {
            if app.isRunning {
                let quit = await AppUninstallerEngine.shared.quitIfRunning(app)
                guard quit else {
                    isUninstalling = false
                    errorMessage = "\(app.name) is still running and couldn't be quit. Quit it, then try again."
                    return
                }
            }

            do {
                let result = try await AppUninstallerEngine.shared.uninstall(app: app, removing: leftovers)
                lastUninstallResult = result
                applications.removeAll { $0.id == app.id }
                relatedFilesByApp[app.id] = nil
                isUninstalling = false
                if !result.failedPaths.isEmpty {
                    errorMessage = "\(result.failedPaths.count) item(s) couldn't be moved to the Trash. Full Disk Access lets CachePop remove everything."
                }
                // Move on from the removed app, but keep another app picked while it was removed.
                if selectedAppID == app.id || selectedApp == nil {
                    selectedAppID = filteredApplications.first?.id
                }
                onSpaceChanged()
            } catch {
                isUninstalling = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
