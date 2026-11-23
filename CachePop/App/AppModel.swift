import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case cleanUp
    case largeFiles
    case photos
    case systemMonitor
    case diskUsage
    case apps
    case loginItems
    /// Shown from the sidebar footer and ⌘, — not one of the numbered sections.
    case settings

    var id: String { rawValue }

    /// The sections listed in the sidebar and the View menu, in order.
    static let navigation: [AppSection] = [.cleanUp, .largeFiles, .photos, .systemMonitor, .diskUsage, .apps, .loginItems]

    var title: String {
        switch self {
        case .cleanUp:    "Clean Up"
        case .largeFiles: "Large Files"
        case .photos:     "Photos"
        case .systemMonitor: "System Monitor"
        case .diskUsage:  "Disk Usage"
        case .apps:       "Applications"
        case .loginItems: "Login Items"
        case .settings:   "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .cleanUp:    "trash"
        case .largeFiles: "doc.on.doc"
        case .photos:     "photo.on.rectangle.angled"
        case .systemMonitor: "gauge.with.dots.needle.50percent"
        case .diskUsage:  "chart.pie"
        case .apps:       "square.grid.2x2"
        case .loginItems: "power"
        case .settings:   "gearshape"
        }
    }

    /// ⌘1 … ⌘7, in sidebar order. Settings uses ⌘, instead.
    var shortcut: KeyEquivalent {
        if self == .settings { return "," }
        return KeyEquivalent(Character(String((Self.navigation.firstIndex(of: self) ?? 0) + 1)))
    }
}

/// Shares services with the menu bar and clears each section's temporary state on navigation.
@Observable
@MainActor
final class AppModel {
    var section: AppSection? = .cleanUp {
        didSet {
            let previous = oldValue ?? .cleanUp
            guard previous != (section ?? .cleanUp) else { return }
            resetSection(previous)
        }
    }
    let settings: AppSettings
    let history: CleanHistory
    let cleanUp: CleanUpViewModel
    let largeFiles: LargeFilesViewModel
    let photos: PhotosViewModel
    let diskUsage: DiskUsageViewModel
    let monitor: SystemMonitorViewModel
    let fanControl: FanControlViewModel
    let apps: AppsViewModel
    let loginItems: LoginItemsViewModel
    private(set) var disk: DiskInfo = .empty
    /// True while the launch screen is showing.
    private(set) var isLaunching = true
    var isShowingHistory = false
    /// Keep the model state, but release the window view graph in background mode.
    private(set) var isMainWindowContentActive = true

    /// Set by views that have SwiftUI's window actions, so the menu bar item, notifications
    /// and menu commands can bring the main window or Settings back.
    @ObservationIgnored var openMainWindow: () -> Void = {}
    @ObservationIgnored var openMenuBarPanel: (StatusMenuKind) -> Void = { _ in }

    private let diskURL: URL
    private let diskReader: @Sendable (URL) async -> DiskInfo
    private let notifications: any NotificationPosting
    private var lowSpaceRule: LowSpaceRule
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var diskReadTask: Task<Void, Never>?
    @ObservationIgnored private var diskRefreshPending = false
    @ObservationIgnored private var memoryTrimTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    init(
        environment: CleanupEnvironment = .live,
        settings: AppSettings? = nil,
        history: CleanHistory? = nil,
        notifications: (any NotificationPosting)? = nil,
        fanController: (any FanControlling)? = nil,
        fanSource: (@Sendable () -> [FanSample])? = nil,
        startupControl: (any StartupControlling)? = nil,
        diskReader: @escaping @Sendable (URL) async -> DiskInfo = { await SystemInfoService.readDisk(for: $0) }
    ) {
        let settings = settings ?? AppSettings()
        let usesLiveHome = environment.home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        diskURL = environment.home
        self.diskReader = diskReader
        self.settings = settings
        lowSpaceRule = settings.savedLowSpaceRule
        self.history = history ?? CleanHistory()
        self.notifications = notifications ?? SystemNotifications()
        cleanUp = CleanUpViewModel(engine: CleanupEngine(env: environment))
        largeFiles = LargeFilesViewModel(home: environment.home, settings: settings)
        // Demo mode runs against a fixture home, and must never read the real Photos library.
        photos = PhotosViewModel(home: environment.home,
                                 allowsLibrary: environment.home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
        diskUsage = DiskUsageViewModel(home: environment.home,
                                      applications: usesLiveHome ? URL(fileURLWithPath: "/Applications") : environment.path("Applications"))
        apps = AppsViewModel(engine: AppUninstallerEngine(home: environment.home,
                             appDirectories: usesLiveHome ? nil : [environment.path("Applications").path]), catalog: environment.apps)
        monitor = SystemMonitorViewModel(fanSource: fanSource)
        fanControl = FanControlViewModel(controller: fanController ?? LiveFanController(), boostRules: settings.fanBoostRules)
        fanControl.onBoostRulesChanged = { [settings] in settings.fanBoostRules = $0 }
        loginItems = LoginItemsViewModel(control: startupControl ?? LiveStartupControl(), home: environment.home)
        loginItems.rememberedOffApps = { [settings] in settings.loginAppsTurnedOff }
        loginItems.setRememberedOffApps = { [settings] in settings.loginAppsTurnedOff = $0 }

        // While fans are on a fixed speed, keep reading temperatures so heat releases them.
        // Weak both ways: each view model's callback would otherwise keep the other alive.
        fanControl.onModeChanged = { [weak monitor] mode in
            // A mode change must keep one client, including switching between the two overrides.
            monitor?.end("fans")
            if mode != .automatic { monitor?.begin("fans") }
        }
        monitor.onSnapshot = { [weak fanControl] snapshot, thermalState in
            fanControl?.receive(snapshot, thermalState: thermalState)
        }

        cleanUp.settingsProvider = { [settings] in settings.cleanupSettings }
        cleanUp.onCleaned = { [weak self] report in
            self?.history.add(report)
            self?.refreshDiskWhileSettling()
        }
        cleanUp.onAlwaysSkip = { [settings] item in settings.neverClean(item: item) }
        largeFiles.onSpaceChanged = { [weak self] in self?.refreshDiskWhileSettling() }
        photos.onSpaceChanged = { [weak self] in self?.refreshDiskWhileSettling() }
        apps.onSpaceChanged = { [weak self] in self?.refreshDiskWhileSettling() }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.trimTransientMemory()
                self?.scheduleMemoryTrim(underPressure: true)
            }
        }
        pressure.activate()
        memoryPressureSource = pressure
    }

    isolated deinit {
        refreshTask?.cancel()
        monitorTask?.cancel()
        diskReadTask?.cancel()
        memoryTrimTask?.cancel()
        memoryPressureSource?.cancel()
    }

    // MARK: Launch

    /// Fades from the launch screen into the app. Called when the launch animation finishes.
    func endLaunch(reduceMotion: Bool = false) {
        guard isLaunching else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45)) {
            isLaunching = false
        }
    }

    /// Safety net: never leave the launch screen up if its animation doesn't report back.
    func finishLaunchIfStuck(reduceMotion: Bool) async {
        guard isLaunching else { return }
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled else { return }
        endLaunch(reduceMotion: reduceMotion)
    }

    // MARK: Disk

    /// Reads free space off the main thread: the important-usage figure asks macOS how much is
    /// purgeable, which can stall (most of all right after a big clean). Concurrent requests
    /// share one read, with at most one follow-up, rather than spawning uncancellable IO jobs.
    func refreshDisk() {
        guard diskReadTask == nil else {
            diskRefreshPending = true
            return
        }
        let url = diskURL
        diskReadTask = Task { [weak self, diskReader] in
            let reading = await diskReader(url)
            guard let self else { return }
            self.diskReadTask = nil
            guard !Task.isCancelled else { return }
            // Publish only a change, so an activation with nothing new redraws nothing.
            if reading != self.disk { self.disk = reading }
            self.checkLowSpace()
            if self.diskRefreshPending {
                self.diskRefreshPending = false
                self.refreshDisk()
            }
        }
    }

    /// APFS keeps handing space back for a little while after big deletions.
    func refreshDiskWhileSettling() {
        refreshDisk()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for delay in [2.0, 5.0, 15.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refreshDisk()
            }
        }
    }

    /// Re-reads free space every few minutes while CachePop runs, for the menu bar and alerts.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        refreshDisk()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, self != nil else { return }
                self?.refreshDisk()
            }
        }
    }

    var lowSpaceThresholdBytes: Int64 {
        settings.lowSpaceThreshold.bytes(totalBytes: disk.totalBytes)
    }

    /// Below the alert threshold right now.
    var isLowOnSpace: Bool {
        disk.totalBytes > 0 && disk.availableBytes < lowSpaceThresholdBytes
    }

    private func checkLowSpace() {
        guard settings.lowSpaceAlerts, disk.totalBytes > 0 else { return }
        let previous = lowSpaceRule
        let shouldNotify = lowSpaceRule.evaluate(availableBytes: disk.availableBytes, thresholdBytes: lowSpaceThresholdBytes, now: Date())
        if previous != lowSpaceRule { settings.savedLowSpaceRule = lowSpaceRule }
        if shouldNotify {
            notifications.postLowSpace(availableBytes: disk.availableBytes)
        }
    }

    func requestNotificationPermission() {
        Task { _ = await notifications.requestPermission() }
    }

    // MARK: Navigation

    private func resetSection(_ section: AppSection) {
        switch section {
        case .cleanUp:
            isShowingHistory = false
            cleanUp.resetForNavigation()
        case .largeFiles: largeFiles.resetForNavigation()
        case .photos: photos.resetForNavigation()
        case .diskUsage: diskUsage.resetForNavigation()
        case .apps: apps.resetForNavigation()
        case .loginItems: loginItems.resetForNavigation()
        case .systemMonitor:
            monitor.activePage = .cpu
            monitor.processToQuit = nil
            monitor.processSort = .cpu
            monitor.scrollToProcesses = false
        case .settings: settings.selectedTab = .general
        }
    }

    /// Brings the main window forward on `section`.
    func show(_ section: AppSection) {
        resumeMainWindowContent()
        NSApp.setActivationPolicy(.regular)
        openMainWindow()
        NSApp.unhide(nil)
        NSApp.activate()
        withAnimation(AppTheme.Motion.standard) { self.section = section }
    }

    /// Dismisses the main app from the Dock and app switcher while its menu bar items keep
    /// running. Reopening a section restores the regular app presentation.
    func keepRunningInMenuBar() {
        guard settings.showsAnyMenuBarItem else {
            quitCompletely()
            return
        }
        suspendMainWindowContent()
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func resumeMainWindowContent() {
        memoryTrimTask?.cancel()
        memoryTrimTask = nil
        isMainWindowContentActive = true
    }

    func suspendMainWindowContent() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { isMainWindowContentActive = false }
        scheduleMemoryTrim()
    }

    /// Discard rebuildable caches, while keeping scans, selections, Put Back and recordings.
    func trimTransientMemory() {
        FileKind.clearCache()
        PhotoThumbnails.clear()
        IconCache.clear()
        apps.releaseRelatedFileCache()
        diskUsage.releaseInactiveListings()
        monitor.releaseUnusedProcessDetails(discardMenuCache: true)
    }

    private func scheduleMemoryTrim(underPressure: Bool = false) {
        memoryTrimTask?.cancel()
        memoryTrimTask = Task { [weak self] in
            // Let SwiftUI finish detaching the window's views before releasing free pages.
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard self != nil, underPressure || self?.isMainWindowContentActive == false else { return }
            self?.trimTransientMemory()
            await MemoryResources.releaseUnusedPages()
        }
    }

    /// Stops the app and its menu bar readings; the delegate first releases custom fan speeds.
    func quitCompletely() {
        NSApp.terminate(nil)
    }

    /// The line under the section's title in the top bar.
    func pageSubtitle(for section: AppSection) -> String {
        section == .settings
            ? ""
            : sidebarStatus(for: section).subtitle
    }

    func showHistory() {
        show(.cleanUp)
        isShowingHistory = true
    }

    /// Opens Clean Up and starts a scan unless one is running or waiting for review.
    func scanForJunk() {
        show(.cleanUp)
        switch cleanUp.phase {
        case .start, .done: cleanUp.scan()
        case .scanning, .review, .cleaning: break
        }
    }

    /// ⌘R: scan again in whichever section is showing.
    func rescanCurrentSection() {
        switch section ?? .cleanUp {
        case .cleanUp:
            if cleanUp.phase != .cleaning && cleanUp.phase != .scanning { cleanUp.scan() }
        case .largeFiles:
            if largeFiles.phase != .scanning { largeFiles.scan() }
        case .photos:
            if photos.phase != .scanning { photos.scan() }
        case .diskUsage:
            diskUsage.rescan()
        case .systemMonitor:
            break
        case .apps:
            apps.scan()
        case .loginItems:
            loginItems.scan()
        case .settings:
            break
        }
    }
}
