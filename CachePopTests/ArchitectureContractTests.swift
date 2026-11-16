import Foundation
import Testing
@testable import CachePop

@Suite("Feature service boundaries")
@MainActor
struct ArchitectureContractTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func largeFilesUsesInjectedScanTrashRestoreAndFolderPicker() async {
        let file = FoundFile(url: URL(fileURLWithPath: "/fixture/movie.mov"), size: 4_096, modified: nil)
        let scanner = ContractLargeScanner(file: file)
        let actions = ContractFileActions()
        let desktop = ContractDesktop()
        let restorer = ContractRestorer()
        let model = LargeFilesViewModel(home: URL(fileURLWithPath: "/fixture"), settings: nil,
                                        scanner: scanner, classifier: ContractClassifier(),
                                        fileActions: actions, restorer: restorer, desktop: desktop)
        model.chooseFolder()
        #expect(model.chosenFolder == desktop.folder)
        model.scan()
        #expect(await eventually { model.phase == .results })
        #expect(await scanner.roots == [desktop.folder])
        model.toggle(file)
        model.moveSelectedToTrash()
        #expect(await eventually { !model.isMoving })
        #expect(actions.paths == [file.url.path])
        #expect(model.result.largeFiles.isEmpty)
        model.putBack()
        #expect(await eventually { !model.isMoving })
        #expect(model.result.largeFiles == [file])
        #expect(await restorer.calls == 1)
    }

    @Test func photoAccessDenialStillScansFoldersThroughInjectedServices() async {
        let scanner = ContractPhotoScanner()
        let desktop = ContractDesktop()
        let model = PhotosViewModel(home: URL(fileURLWithPath: "/fixture"), allowsLibrary: true,
                                    scanner: scanner, library: ContractPhotoLibrary(),
                                    fileActions: ContractFileActions(), restorer: ContractRestorer(),
                                    desktop: desktop, clearThumbnails: {})
        model.scan()
        #expect(await eventually { model.phase == .results })
        #expect(model.libraryAccessDenied)
        #expect(await scanner.includedLibrary == false)
        #expect(await scanner.calls == 1)
        model.openPhotosSettings()
        #expect(desktop.opened?.absoluteString.contains("Privacy_Photos") == true)
    }

    @Test func diskUsageReceivesMeasurementsWithoutReadingRealFolders() async {
        let folder = URL(fileURLWithPath: "/fixture")
        let model = DiskUsageViewModel(home: folder, applications: folder.appendingPathComponent("Apps"),
                                       measurer: ContractDiskMeasurer())
        model.start()
        #expect(await eventually { model.phase == .ready })
        #expect(model.currentEntries.count == 1)
        #expect(model.currentEntries.first?.bytes == 4_096)
        model.resetForNavigation()
        #expect(model.phase == .start)
        #expect(model.currentEntries.isEmpty)
    }

    @Test func applicationFlowUsesAnInjectedManager() async {
        let manager = ContractApplicationManager()
        let model = AppsViewModel(engine: manager, catalog: ContractCatalog())
        model.scan()
        #expect(await eventually { model.hasScanned && !model.isScanning })
        #expect(model.selectedApp?.id == manager.application.id)
        model.confirmUninstall()
        #expect(await eventually { !model.isUninstalling })
        #expect(manager.uninstallCalls == 1)
        #expect(model.applications.isEmpty)
    }

    @Test func settingsWritesAndLoginRegistrationUseTheirPorts() {
        let store = ContractSettingsStore()
        let login = ContractLoginController()
        let settings = AppSettings(store: store, loginItem: login, canChangeLoginItem: true)
        settings.appearance = .dark
        #expect(store.string(forKey: "appearance") == "dark")
        settings.showMenuBarItem = false
        settings.opensAtLogin = true
        #expect(settings.opensAtLogin)
        #expect(settings.showMenuBarItem)
        #expect(login.requests == [true])
        let disabled = AppSettings(store: store, loginItem: login, canChangeLoginItem: false)
        disabled.opensAtLogin = false
        #expect(login.requests == [true], "Demo/test preferences must not register system login items.")
    }

    @Test func historyPresentationUsesValueEntriesAndInjectedStorage() {
        let entry = CleanHistoryEntry(id: "existing", date: Date(), freedBytes: 42, wasMeasured: true,
                                      itemCount: 1, trashBytes: 0, titles: ["Caches"])
        let store = ContractHistoryStore(entries: [entry])
        let history = CleanHistory(store: store)
        #expect(history.lastClean == entry)
        #expect(history.lifetimeFreedBytes == 42)
        history.clear()
        #expect(store.entries.isEmpty)
        #expect(history.records.isEmpty)
    }

    @Test func monitorUsesInjectedProcessControlAndProcessorIdentity() {
        let controller = ContractProcessController()
        let model = SystemMonitorViewModel(sampler: ContractSystemSampler(),
                                            processor: ProcessorIdentity(name: "Fixture CPU", performanceCores: 2,
                                                                         efficiencyCores: 4, topology: [0: .efficiency]),
                                            processApplications: controller)
        let process = ProcessUsage(pid: 123, name: "Fixture", cpuPercent: 0, memoryBytes: 0)
        #expect(model.chipName == "Fixture CPU")
        #expect(model.cores.efficiency == 4)
        #expect(model.canQuit(process))
        model.processToQuit = process
        model.quit(process)
        #expect(controller.quitPIDs == [123])
        #expect(model.processToQuit == nil)
        model.releaseUnusedProcessDetails()
        #expect(controller.releases == 1)
    }
}

private actor ContractLargeScanner: LargeFilesScanning {
    let file: FoundFile
    var roots: [URL] = []
    init(file: FoundFile) { self.file = file }
    nonisolated func defaultRoots(home: URL) -> [URL] { [home] }
    func scan(roots: [URL], threshold: Int64, progress: @escaping @Sendable (String) -> Void) async -> LargeFilesResult {
        self.roots = roots
        return LargeFilesResult(largeFiles: [file])
    }
}
private nonisolated struct ContractClassifier: FileClassifying {
    func kind(of url: URL) -> FileKind { .videos }
}
@MainActor
private final class ContractDesktop: DesktopInteracting {
    let folder = URL(fileURLWithPath: "/fixture/chosen")
    var opened: URL?
    func chooseFolder(startingAt url: URL, message: String) -> URL? { folder }
    func open(_ url: URL) { opened = url }
}
@MainActor
private final class ContractFileActions: FileActionPerforming {
    var paths: [String] = []
    func moveToTrash(paths: [String], reviewed: [String: FileReviewIdentity]) async -> FileActionResult {
        self.paths = paths
        return FileActionResult(bytesFreed: 4_096, itemsRemoved: paths.count, errors: [],
                                trashed: paths.map { TrashedItem(original: URL(fileURLWithPath: $0),
                                                                trashed: URL(fileURLWithPath: "/fixture/trash/movie.mov")) })
    }
}
private actor ContractRestorer: TrashRestoring {
    var calls = 0
    func restore(_ items: [TrashedItem]) async -> RestoreOutcome {
        calls += 1
        return RestoreOutcome(restored: items)
    }
}
private actor ContractPhotoScanner: PhotoScanning {
    var calls = 0
    var includedLibrary: Bool?
    nonisolated func folders(home: URL) -> [URL] { [home] }
    func scan(folders: [URL], includeLibrary: Bool, progress: @escaping @Sendable (Int, Int) -> Void) async -> PhotoScanResult {
        calls += 1
        includedLibrary = includeLibrary
        return .empty
    }
}
private nonisolated struct ContractPhotoLibrary: PhotoLibraryManaging {
    func requestAccess() async -> Bool { false }
    func delete(_ identifiers: [String]) async throws {}
}
private nonisolated struct ContractDiskMeasurer: DiskUsageMeasuring {
    func entries(in folder: URL, adding extra: [UsageEntry]) async -> [UsageEntry] {
        [UsageEntry(url: folder.appendingPathComponent("sample"), isDirectory: false)]
    }
    func measure(_ entries: [UsageEntry], onMeasured: @escaping @Sendable (UsageEntry) async -> Void) async {
        for var entry in entries { entry.bytes = 4_096; await onMeasured(entry) }
    }
}
@MainActor
private final class ContractApplicationManager: ApplicationManaging {
    let application = ApplicationDetails(id: "fixture", name: "Fixture", path: "/fixture/Fixture.app",
                                         bundleIdentifier: "example.fixture", version: "1", sizeBytes: 42, lastUsedDate: nil)
    var uninstallCalls = 0
    func scanApplications() async -> [ApplicationDetails] { [application] }
    func findRelatedFiles(for app: ApplicationDetails, installedBundleIDs: Set<String>?, priority: TaskPriority) async -> [ApplicationRelatedFile] { [] }
    func isRunning(_ app: ApplicationDetails) -> Bool { false }
    func quitIfRunning(_ app: ApplicationDetails) async -> Bool { true }
    func uninstall(app: ApplicationDetails, removing relatedFiles: [ApplicationRelatedFile]) async throws -> UninstallResult {
        uninstallCalls += 1
        return UninstallResult(app: app, bytesFreed: 42, filesRemoved: 1, failedPaths: [])
    }
}
private nonisolated struct ContractCatalog: AppCataloging {
    func installedBundleIDs() -> Set<String> { [] }
    func isKnown(bundleID: String) -> Bool { false }
}
@MainActor
private final class ContractSettingsStore: SettingsStoring {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
@MainActor
private final class ContractLoginController: AppLoginControlling {
    var requests: [Bool] = []
    var status: AppLoginStatus = .disabled
    func setEnabled(_ enabled: Bool) throws { requests.append(enabled); status = enabled ? .enabled : .disabled }
}
@MainActor
private final class ContractHistoryStore: CleanHistoryStoring {
    var entries: [CleanHistoryEntry]
    init(entries: [CleanHistoryEntry]) { self.entries = entries }
    func fetch() -> [CleanHistoryEntry] { entries }
    func insert(_ entry: CleanHistoryEntry) { entries.insert(entry, at: 0) }
    func clear() { entries = [] }
}

private actor ContractSystemSampler: SystemSampling {
    func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot { SystemSnapshot() }
}
@MainActor
private final class ContractProcessController: ProcessApplicationControlling {
    var quitPIDs: [Int32] = []
    var releases = 0
    func canQuit(pid: Int32) -> Bool { pid == 123 }
    func quit(pid: Int32) { quitPIDs.append(pid) }
    func retainDetails(for processIDs: Set<Int32>) {}
    func releaseDetails() { releases += 1 }
}
