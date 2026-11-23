import Foundation
import Observation

/// The tabs of the Settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, menuBar, cleanUp, neverClean, largeFiles
    var id: String { rawValue }
}


/// Everything the user can change in Settings, saved in `UserDefaults`.
///
/// Demo mode and tests pass their own defaults suite so the real preferences are never touched.
@Observable
@MainActor
final class AppSettings: LargeFilePreferencesProviding {
    @ObservationIgnored private let defaults: any SettingsStoring
    @ObservationIgnored private let loginItem: any AppLoginControlling

    /// Which Settings tab is showing (not saved).
    var selectedTab: SettingsTab = .general

    /// Light, dark or the Mac's setting. Applied by the app (`AppearanceMode.apply()`), not here,
    /// so tests can change it without restyling the test host.
    var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem") } }
    var menuBarShowsCPUUsage: Bool { didSet { save(menuBarShowsCPUUsage, "menuBarShowsCPUUsage") } }
    var menuBarShowsGPUUsage: Bool { didSet { save(menuBarShowsGPUUsage, "menuBarShowsGPUUsage") } }
    var menuBarShowsSensors: Bool { didSet { save(menuBarShowsSensors, "menuBarShowsSensors") } }
    var menuBarShowsNetwork: Bool { didSet { save(menuBarShowsNetwork, "menuBarShowsNetwork") } }
    var menuBarShowsBattery: Bool { didSet { save(menuBarShowsBattery, "menuBarShowsBattery") } }
    var menuBarShowsMemoryUsage: Bool { didSet { save(menuBarShowsMemoryUsage, "menuBarShowsMemoryUsage") } }
    var menuBarShowsSSDUsage: Bool { didSet { save(menuBarShowsSSDUsage, "menuBarShowsSSDUsage") } }
    /// The chip temperature in a menu bar item of its own.
    var menuBarShowsTemperature: Bool { didSet { save(menuBarShowsTemperature, "menuBarShowsTemperature") } }
    /// The fastest fan's speed in a menu bar item of its own.
    var menuBarShowsFanSpeed: Bool { didSet { save(menuBarShowsFanSpeed, "menuBarShowsFanSpeed") } }
    var fanBoostRules: [FanBoostRule] {
        didSet { defaults.set(try? JSONEncoder().encode(fanBoostRules), forKey: "fanBoostRules") }
    }
    var lowSpaceAlerts: Bool { didSet { save(lowSpaceAlerts, "lowSpaceAlerts") } }
    var lowSpaceThreshold: LowSpaceThreshold { didSet { save(lowSpaceThreshold.rawValue, "lowSpaceThreshold") } }
    var redownloadThreshold: RedownloadThreshold { didSet { save(redownloadThreshold.rawValue, "redownloadThresholdMB") } }
    /// Logs younger than this many days are kept.
    var logAgeDays: Int { didSet { save(logAgeDays, "logAgeDays") } }
    var largeFileMinimumMB: Int { didSet { save(largeFileMinimumMB, "largeFileMinimumMB") } }
    /// Folders Large Files looks in. Empty means the standard home folders.
    var largeFileFolders: [String] { didSet { save(largeFileFolders, "largeFileFolders") } }
    /// Open at Login apps CachePop turned off (bundle paths), so Login Items can still list
    /// them and turn them back on.
    var loginAppsTurnedOff: [String] { didSet { save(loginAppsTurnedOff, "loginAppsTurnedOff") } }
    var neverClean: [NeverCleanEntry] {
        didSet { defaults.set(try? JSONEncoder().encode(neverClean), forKey: "neverClean") }
    }

    /// Whether "Open at login" can be changed (not in demo mode or tests).
    let canChangeLoginItem: Bool

    init(store: any SettingsStoring, loginItem: any AppLoginControlling, canChangeLoginItem: Bool) {
        let defaults = store
        self.defaults = store
        self.loginItem = loginItem
        self.canChangeLoginItem = canChangeLoginItem
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        menuBarShowsCPUUsage = defaults.object(forKey: "menuBarShowsCPUUsage") as? Bool ?? false
        menuBarShowsGPUUsage = defaults.object(forKey: "menuBarShowsGPUUsage") as? Bool ?? false
        menuBarShowsSensors = defaults.object(forKey: "menuBarShowsSensors") as? Bool ?? false
        menuBarShowsNetwork = defaults.object(forKey: "menuBarShowsNetwork") as? Bool ?? false
        menuBarShowsBattery = defaults.object(forKey: "menuBarShowsBattery") as? Bool ?? false
        menuBarShowsMemoryUsage = defaults.object(forKey: "menuBarShowsMemoryUsage") as? Bool ?? false
        menuBarShowsSSDUsage = defaults.object(forKey: "menuBarShowsSSDUsage") as? Bool ?? false
        menuBarShowsTemperature = defaults.object(forKey: "menuBarShowsTemperature") as? Bool ?? false
        menuBarShowsFanSpeed = defaults.object(forKey: "menuBarShowsFanSpeed") as? Bool ?? false
        fanBoostRules = defaults.data(forKey: "fanBoostRules")
            .flatMap { try? JSONDecoder().decode([FanBoostRule].self, from: $0) } ?? FanBoostRule.defaults
        lowSpaceAlerts = defaults.object(forKey: "lowSpaceAlerts") as? Bool ?? true
        lowSpaceThreshold = LowSpaceThreshold(rawValue: defaults.object(forKey: "lowSpaceThreshold") as? Int ?? 0) ?? .tenPercent
        redownloadThreshold = RedownloadThreshold(rawValue: defaults.object(forKey: "redownloadThresholdMB") as? Int ?? 100) ?? .mb100
        logAgeDays = defaults.object(forKey: "logAgeDays") as? Int ?? 7
        largeFileMinimumMB = defaults.object(forKey: "largeFileMinimumMB") as? Int ?? 100
        largeFileFolders = defaults.stringArray(forKey: "largeFileFolders") ?? []
        loginAppsTurnedOff = defaults.stringArray(forKey: "loginAppsTurnedOff") ?? []
        neverClean = (defaults.data(forKey: "neverClean")).flatMap { try? JSONDecoder().decode([NeverCleanEntry].self, from: $0) } ?? []
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// Keep the once-per-drop, at-most-daily alert policy across app relaunches.
    var savedLowSpaceRule: LowSpaceRule {
        get {
            defaults.data(forKey: "lowSpaceAlertState")
                .flatMap { try? JSONDecoder().decode(LowSpaceRule.self, from: $0) } ?? LowSpaceRule()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "lowSpaceAlertState") }
    }

    // MARK: Never Clean

    func neverClean(folder url: URL) {
        let entry = NeverCleanEntry(kind: .folder, value: url.path, title: url.path)
        if !neverClean.contains(entry) { neverClean.append(entry) }
    }

    func neverClean(item: CleanupItem) {
        let entry = NeverCleanEntry(kind: .item, value: item.id, title: item.title)
        if !neverClean.contains(where: { $0.kind == .item && $0.value == item.id }) { neverClean.append(entry) }
    }

    func remove(_ entry: NeverCleanEntry) {
        neverClean.removeAll { $0 == entry }
    }

    // MARK: For the engine

    var cleanupSettings: CleanupSettings {
        CleanupSettings(
            largeDownloadThreshold: redownloadThreshold.bytes,
            logAge: TimeInterval(logAgeDays) * 86_400,
            neverClean: NeverCleanList(
                folders: neverClean.filter { $0.kind == .folder }.map { URL(fileURLWithPath: $0.value, isDirectory: true) },
                itemIDs: Set(neverClean.filter { $0.kind == .item }.map(\.value))
            )
        )
    }

    var largeFileThreshold: Int64 { Int64(largeFileMinimumMB) * 1_048_576 }

    /// Live readings stay available when ⌘Q dismisses the main app into the menu bar.
    var showsMenuBarReadings: Bool {
        menuBarShowsCPUUsage || menuBarShowsGPUUsage || menuBarShowsBattery || menuBarShowsMemoryUsage || menuBarShowsSSDUsage
            || menuBarShowsTemperature || menuBarShowsFanSpeed || menuBarShowsSensors || menuBarShowsNetwork
    }

    /// Whether CachePop's icon or any live reading shows in the menu bar.
    /// While one does, CachePop keeps running with its window closed.
    var showsAnyMenuBarItem: Bool {
        showMenuBarItem || showsMenuBarReadings
    }

    // MARK: Open at login

    /// Opened at login, CachePop starts hidden, so its menu bar item stays on: it's the way back
    /// in. (Never in tests or demo mode, which can't change the login item.)
    var menuBarItemIsRequired: Bool { canChangeLoginItem && opensAtLogin }

    var opensAtLogin: Bool {
        get {
            _ = loginItemRevision
            return loginItem.status == .enabled
        }
        set {
            guard canChangeLoginItem else { return }
            // An earlier failure mustn't stay on screen after this attempt.
            loginItemError = nil
            // Starting hidden needs CachePop's menu bar item to open it from.
            if newValue { showMenuBarItem = true }
            do {
                try loginItem.setEnabled(newValue)
                // Registered, but switched off in System Settings: the switch would just flip back.
                if newValue, loginItem.status == .needsApproval {
                    loginItemError = "Turn CachePop on in System Settings › General › Login Items to open it at login."
                }
            } catch {
                loginItemError = error.localizedDescription
            }
            loginItemRevision += 1
        }
    }

    /// Bumped when the login item changes, so views re-read `opensAtLogin`.
    private var loginItemRevision = 0
    var loginItemError: String?
}
