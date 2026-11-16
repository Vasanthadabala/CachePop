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
    private let listing: any LoginItemsListing
    /// Open at Login apps CachePop turned off, kept so they can be turned back on (macOS
    /// forgets them once they're off the list).
    @ObservationIgnored var rememberedOffApps: () -> [String] = { [] }
    @ObservationIgnored var setRememberedOffApps: ([String]) -> Void = { _ in }

    @ObservationIgnored private var task: Task<Void, Never>?

    isolated deinit { task?.cancel() }
    /// A rescan asked for while a switch was still changing the system; it runs once that's done.
    @ObservationIgnored private var rescanWhenIdle = false
    @ObservationIgnored private var resetWhenIdle = false

    init(control: any StartupControlling, listing: any LoginItemsListing) {
        self.control = control
        self.listing = listing
    }

    var agents: [LoginItem] { items.filter(\.isAgent) }
    var apps: [LoginItem] { items.filter { !$0.isAgent } }
    var onCount: Int { items.filter(\.isOn).count }

    func resetForNavigation() {
        task?.cancel()
        task = nil
        isScanning = false
        rescanWhenIdle = false
        guard busyIDs.isEmpty else {
            resetWhenIdle = true
            return
        }
        resetWhenIdle = false
        items = []
        hiddenCount = 0
        hasScanned = false
        appsAccess = .unknown
        message = nil
        scrollToApps = false
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
        let remembered = rememberedOffApps()
        task = Task { [weak self, control, listing] in
            let overrides = await control.overrides()
            guard !Task.isCancelled else { return }
            let agents = await listing.agents(overrides: overrides)
            guard !Task.isCancelled else { return }

            var appItems: [LoginItem] = []
            var access: AppsAccess = .unknown
            var retainedOffApps: [String]?
            do {
                let openAtLogin = try await control.openAtLoginApps()
                guard !Task.isCancelled else { return }
                access = .allowed
                let listed = await listing.apps(openAtLogin, remembering: remembered)
                appItems = listed.items
                retainedOffApps = listed.remembered
            } catch {
                access = error as? StartupControlError == .notAllowed ? .denied : .unknown
            }
            guard let self, !Task.isCancelled else { return }
            self.appsAccess = access
            if let retainedOffApps { self.setRememberedOffApps(retainedOffApps) }
            let listedAgents = agents.filter(\.isListed)
            self.hiddenCount = agents.count - listedAgents.count
            var seen = Set<String>()
            self.items = (listedAgents + appItems)
                .filter { seen.insert($0.path.lowercased()).inserted }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            self.isScanning = false
            self.hasScanned = true
            self.task = nil
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
            if busyIDs.isEmpty {
                if resetWhenIdle { resetForNavigation() }
                else if rescanWhenIdle {
                    rescanWhenIdle = false
                    scan()
                }
            }
        }
    }

    private func update(_ id: String, _ change: (inout LoginItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(AppTheme.Motion.quick) { change(&items[index]) }
    }
}
