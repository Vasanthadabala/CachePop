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

/// Owns one view model per section, so switching sections never loses a scan in progress
/// or a half-made selection. Shared by the main window, the menu bar item and Settings.
@Observable
@MainActor
final class AppModel {
    var section: AppSection? = .cleanUp
    let settings: AppSettings
    let history: CleanHistory
    let cleanUp: CleanUpViewModel
    let largeFiles: LargeFilesViewModel
    let photos: PhotosViewModel
    let diskUsage: DiskUsageViewModel
    let monitor: SystemMonitorViewModel
    let fanControl: FanControlViewModel
    let apps = AppsViewModel()
    let loginItems: LoginItemsViewModel
    private(set) var disk: DiskInfo = .empty
    /// True while the launch screen is showing.
    private(set) var isLaunching = true
    var isShowingHistory = false

    /// Set by views that have SwiftUI's window actions, so the menu bar item, notifications
    /// and menu commands can bring the main window or Settings back.
    @ObservationIgnored var openMainWindow: () -> Void = {}

    private let diskURL: URL
    private let notifications: any NotificationPosting
    private var lowSpaceRule = LowSpaceRule()
    private var refreshTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var diskReadTask: Task<Void, Never>?

    init(
        environment: CleanupEnvironment = .live,
        settings: AppSettings? = nil,
        history: CleanHistory? = nil,
        notifications: (any NotificationPosting)? = nil,
        fanController: (any FanControlling)? = nil,
        fanSource: (@Sendable () -> [FanSample])? = nil,
        startupControl: (any StartupControlling)? = nil
    ) {
        let settings = settings ?? AppSettings()
        diskURL = environment.home
        self.settings = settings
        self.history = history ?? CleanHistory()
        self.notifications = notifications ?? SystemNotifications()
        cleanUp = CleanUpViewModel(engine: CleanupEngine(env: environment))
        largeFiles = LargeFilesViewModel(home: environment.home, settings: settings)
        // Demo mode runs against a fixture home, and must never read the real Photos library.
        photos = PhotosViewModel(home: environment.home,
                                 allowsLibrary: environment.home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL)
        diskUsage = DiskUsageViewModel(home: environment.home)
        monitor = SystemMonitorViewModel(fanSource: fanSource)
        fanControl = FanControlViewModel(controller: fanController ?? LiveFanController())
        loginItems = LoginItemsViewModel(control: startupControl ?? LiveStartupControl())
        loginItems.rememberedOffApps = { [settings] in settings.loginAppsTurnedOff }
        loginItems.setRememberedOffApps = { [settings] in settings.loginAppsTurnedOff = $0 }

        // While fans are on a fixed speed, keep reading temperatures so heat releases them.
        // Weak both ways: each view model's callback would otherwise keep the other alive.
        fanControl.onModeChanged = { [weak monitor] mode in
            if mode == .custom { monitor?.begin("fans") } else { monitor?.end("fans") }
        }
        monitor.onSnapshot = { [weak fanControl] snapshot, thermalState in
            // Only fixed speeds need the heat check; skip a task per sample otherwise.
            guard let fanControl, fanControl.isCustom else { return }
            Task { await fanControl.checkSafety(temperatures: snapshot.temperatures, thermalState: thermalState) }
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
        endLaunch(reduceMotion: reduceMotion)
    }

    // MARK: Disk

    /// Reads free space off the main thread: the important-usage figure asks macOS how much is
    /// purgeable, which can stall (most of all right after a big clean). The newest read wins.
    func refreshDisk() {
        diskReadTask?.cancel()
        let url = diskURL
        diskReadTask = Task {
            let reading = await Task.detached(priority: .userInitiated) { SystemInfoService.disk(for: url) }.value
            guard !Task.isCancelled else { return }
            // Publish only a change, so an activation with nothing new redraws nothing.
            if reading != disk { disk = reading }
            checkLowSpace()
        }
    }

    /// APFS keeps handing space back for a little while after big deletions.
    func refreshDiskWhileSettling() {
        refreshDisk()
        refreshTask?.cancel()
        refreshTask = Task {
            for delay in [2.0, 5.0, 15.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                refreshDisk()
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
                guard let self else { return }
                refreshDisk()
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
        if lowSpaceRule.evaluate(availableBytes: disk.availableBytes, thresholdBytes: lowSpaceThresholdBytes, now: Date()) {
            notifications.postLowSpace(availableBytes: disk.availableBytes)
        }
    }

    func requestNotificationPermission() {
        Task { _ = await notifications.requestPermission() }
    }

    // MARK: Navigation

    /// Brings the main window forward on `section`.
    func show(_ section: AppSection) {
        openMainWindow()
        NSApp.activate()
        withAnimation(AppTheme.Motion.standard) { self.section = section }
    }

    /// The line under the section's title in the top bar.
    func pageSubtitle(for section: AppSection) -> String {
        section == .settings
            ? "Appearance, startup, alerts and what CachePop may clean"
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
