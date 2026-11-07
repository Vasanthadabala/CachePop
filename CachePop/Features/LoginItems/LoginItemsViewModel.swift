import SwiftUI

@Observable
@MainActor
final class LoginItemsViewModel {
    /// Whether CachePop could read the Open at Login list.
    enum AppsAccess { case unknown, allowed, denied }

    private(set) var items: [LoginItem] = []
    /// Agents left out: helpers that only run when their app asks, app services and empty
    /// files. Switching them would break apps or do nothing.
    private(set) var hiddenCount = 0
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var appsAccess: AppsAccess = .unknown
    /// Items whose change is in progress; their switches wait.
    private(set) var busyIDs: Set<String> = []
    var message: String?
    /// Set to scroll to the Applications section (used by the screenshot tour).
    var scrollToApps = false

    private let control: any StartupControlling
    private let home: URL
    /// Open at Login apps CachePop turned off, kept so they can be turned back on (macOS
    /// forgets them once they're off the list).
    @ObservationIgnored var rememberedOffApps: () -> [String] = { [] }
    @ObservationIgnored var setRememberedOffApps: ([String]) -> Void = { _ in }

    private var task: Task<Void, Never>?
    /// A rescan asked for while a switch was still changing the system; it runs once that's done.
    @ObservationIgnored private var rescanWhenIdle = false

    init(control: any StartupControlling = LiveStartupControl(),
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.control = control
        self.home = home
    }

    var agents: [LoginItem] { items.filter(\.isAgent) }
    var apps: [LoginItem] { items.filter { !$0.isAgent } }
    var onCount: Int { items.filter(\.isOn).count }

    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        scan()
    }

    func scan() {
        // Read mid-change, the system would show the old state, and an app just turned off
        // could drop out of the remembered list. Read it once the switches are done.
        guard busyIDs.isEmpty else {
            rescanWhenIdle = true
            return
        }
        task?.cancel()
        isScanning = true
        task = Task {
            let overrides = await control.overrides()
            let agents = await Task.detached(priority: .userInitiated) { [home] in
                LoginItemsScanner.agents(home: home, overrides: overrides)
            }.value

            var appItems: [LoginItem] = []
            do {
                let openAtLogin = try await control.openAtLoginApps()
                appsAccess = .allowed
                appItems = openAtLogin.map {
                    LoginItem(title: ApplicationDetails.cleanName($0.name) ?? $0.name, path: $0.path, kind: .openAtLogin, appPath: $0.path)
                }
                let listed = Set(openAtLogin.map(\.path))
                // Ones CachePop turned off, while the app is still installed.
                let remembered = rememberedOffApps().filter { !listed.contains($0) && FileManager.default.fileExists(atPath: $0) }
                setRememberedOffApps(remembered)
                appItems += remembered.map {
                    LoginItem(title: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent,
                              path: $0, kind: .openAtLogin, appPath: $0, isOn: false)
                }
            } catch {
                appsAccess = error as? StartupControlError == .notAllowed ? .denied : .unknown
            }
            guard !Task.isCancelled else { return }
            let listedAgents = agents.filter(\.isListed)
            hiddenCount = agents.count - listedAgents.count
            var seen = Set<String>()
            items = (listedAgents + appItems)
                .filter { seen.insert($0.path.lowercased()).inserted }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            isScanning = false
            hasScanned = true
        }
    }

    /// Switches an item on or off. The switch moves at once and moves back if macOS refuses.
    /// Not while a scan runs: it read the system before this change and would show it undone.
    func set(_ item: LoginItem, on: Bool) {
        guard item.canToggle, item.isOn != on, !busyIDs.contains(item.id), !isScanning else { return }
        busyIDs.insert(item.id)
        update(item.id) { $0.isOn = on }
        message = nil

        Task {
            do {
                try await control.set(item, on: on)
                if item.kind == .openAtLogin {
                    var remembered = rememberedOffApps().filter { $0 != item.path }
                    if !on { remembered.append(item.path) }
                    setRememberedOffApps(remembered)
                }
            } catch {
                update(item.id) { $0.isOn = !on }
                if let error = error as? StartupControlError {
                    if error == .notAllowed { appsAccess = .denied }
                    if error != .cancelled {
                        message = "Couldn't turn \(on ? "on" : "off") \(item.title). \(error.localizedDescription)"
                    }
                } else {
                    message = "Couldn't turn \(on ? "on" : "off") \(item.title). \(error.localizedDescription)"
                }
            }
            busyIDs.remove(item.id)
            if busyIDs.isEmpty, rescanWhenIdle {
                rescanWhenIdle = false
                scan()
            }
        }
    }

    private func update(_ id: String, _ change: (inout LoginItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(AppTheme.Motion.quick) { change(&items[index]) }
    }
}
