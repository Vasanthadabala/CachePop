import Foundation

// Live defaults are assembled here, never inside feature ViewModels. Explicit designated
// initializers accept ports so tests and demo mode can replace every external operation.
extension CleanUpViewModel {
    convenience init(engine: any CleanupServicing = CleanupEngine()) {
        self.init(engine: engine, restorer: LiveTrashRestorer())
    }
}
extension AppsViewModel {
    convenience init(engine: AppUninstallerEngine? = nil, catalog: any AppCataloging = LiveAppCatalog()) {
        self.init(engine: (engine ?? .shared) as any ApplicationManaging, catalog: catalog)
    }
}
extension DiskUsageViewModel {
    convenience init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     applications: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)) {
        self.init(home: home, applications: applications, measurer: LiveDiskUsageMeasurer())
    }
}
extension LargeFilesViewModel {
    convenience init(home: URL = FileManager.default.homeDirectoryForCurrentUser, settings: AppSettings? = nil) {
        self.init(home: home, settings: settings, scanner: LiveLargeFilesScanner(), classifier: SystemFileClassifier(),
                  fileActions: FileActionService.shared, restorer: LiveTrashRestorer(), desktop: MacDesktopInteraction())
    }
}
extension PhotosViewModel {
    convenience init(home: URL = FileManager.default.homeDirectoryForCurrentUser, allowsLibrary: Bool = true) {
        self.init(home: home, allowsLibrary: allowsLibrary, scanner: LivePhotoScanner(), library: LivePhotoLibrary(),
                  fileActions: FileActionService.shared, restorer: LiveTrashRestorer(),
                  desktop: MacDesktopInteraction(), clearThumbnails: PhotoThumbnails.clear)
    }
}
extension SystemMonitorViewModel {
    convenience init(fanSource: (@Sendable () -> [FanSample])? = nil, sampler: (any SystemSampling)? = nil) {
        let counts = CPUReader.coreKinds()
        self.init(sampler: sampler ?? SystemSampler(fanSource: fanSource),
                  processor: ProcessorIdentity(name: CPUReader.name, performanceCores: counts.performance,
                                               efficiencyCores: counts.efficiency, topology: CPUCoreTopology.read()),
                  processApplications: MacProcessApplicationController())
    }
}
extension AppSettings {
    convenience init(defaults: UserDefaults = .standard, canChangeLoginItem: Bool = true) {
        self.init(store: UserDefaultsSettingsStore(defaults: defaults), loginItem: SystemAppLoginController(),
                  canChangeLoginItem: canChangeLoginItem)
    }
}

extension LoginItemsViewModel {
    convenience init(control: any StartupControlling = LiveStartupControl(),
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(control: control, listing: LiveLoginItemsListing(home: home))
    }
}
extension CleanHistory {
    convenience init(inMemory: Bool = false) { self.init(store: SwiftDataHistoryStore(inMemory: inMemory)) }
}
extension PermissionsManager {
    static let shared = PermissionsManager(checker: LivePermissionChecker(), desktop: MacDesktopInteraction())
}
