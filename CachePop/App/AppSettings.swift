import Foundation
import Observation
import ServiceManagement

/// Something the user told CachePop never to clean: a folder, or one item from a scan.
struct NeverCleanEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case folder, item }

    let kind: Kind
    /// A folder path, or an item ID such as "general.appCaches".
    let value: String
    /// What to show in Settings: the folder's path or the item's title.
    let title: String

    var id: String { "\(kind.rawValue):\(value)" }
}

/// When to untick data that has to be downloaded again.
enum RedownloadThreshold: Int, CaseIterable, Identifiable {
    case mb50 = 50, mb100 = 100, mb250 = 250, mb500 = 500, gb1 = 1000, never = 0

    var id: Int { rawValue }
    var bytes: Int64? { self == .never ? nil : Int64(rawValue) * 1_000_000 }
    var title: String {
        switch self {
        case .never: "Never — keep them ticked"
        case .gb1:   "Over 1 GB"
        default:     "Over \(rawValue) MB"
        }
    }
}

/// When to warn that the disk is nearly full.
enum LowSpaceThreshold: Int, CaseIterable, Identifiable {
    case tenPercent = 0, gb5 = 5, gb10 = 10, gb20 = 20, gb50 = 50

    var id: Int { rawValue }
    var title: String {
        self == .tenPercent ? "Under 10% of the disk" : "Under \(rawValue) GB"
    }

    func bytes(totalBytes: Int64) -> Int64 {
        self == .tenPercent ? totalBytes / 10 : Int64(rawValue) * 1_000_000_000
    }
}

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
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// Which Settings tab is showing (not saved).
    var selectedTab: SettingsTab = .general

    /// Light, dark or the Mac's setting. Applied by the app (`AppearanceMode.apply()`), not here,
    /// so tests can change it without restyling the test host.
    var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem") } }
    /// The chip temperature in a menu bar item of its own.
    var menuBarShowsTemperature: Bool { didSet { save(menuBarShowsTemperature, "menuBarShowsTemperature") } }
    /// The fastest fan's speed in a menu bar item of its own.
    var menuBarShowsFanSpeed: Bool { didSet { save(menuBarShowsFanSpeed, "menuBarShowsFanSpeed") } }
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

    init(defaults: UserDefaults = .standard, canChangeLoginItem: Bool = true) {
        self.defaults = defaults
        self.canChangeLoginItem = canChangeLoginItem
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        menuBarShowsTemperature = defaults.object(forKey: "menuBarShowsTemperature") as? Bool ?? false
        menuBarShowsFanSpeed = defaults.object(forKey: "menuBarShowsFanSpeed") as? Bool ?? false
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

    /// Whether any of CachePop's menu bar items shows (its icon, the temperature, the fan speed).
    /// While one does, CachePop keeps running with its window closed.
    var showsAnyMenuBarItem: Bool {
        showMenuBarItem || menuBarShowsTemperature || menuBarShowsFanSpeed
    }

    // MARK: Open at login

    /// Opened at login, CachePop starts hidden, so its menu bar item stays on: it's the way back
    /// in. (Never in tests or demo mode, which can't change the login item.)
    var menuBarItemIsRequired: Bool { canChangeLoginItem && opensAtLogin }

    var opensAtLogin: Bool {
        get {
            _ = loginItemRevision
            return SMAppService.mainApp.status == .enabled
        }
        set {
            guard canChangeLoginItem else { return }
            // An earlier failure mustn't stay on screen after this attempt.
            loginItemError = nil
            // Starting hidden needs CachePop's menu bar item to open it from.
            if newValue { showMenuBarItem = true }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                // Registered, but switched off in System Settings: the switch would just flip back.
                if newValue, SMAppService.mainApp.status == .requiresApproval {
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
