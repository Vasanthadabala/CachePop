import AppKit
import Observation
import SwiftUI

/// Each component owns a native button and accessibility target; all share one focused popover.
@MainActor
final class UsageMenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private var items: [UsageMenuKind: NSStatusItem] = [:]
    private var visibility: [UsageMenuKind: NSKeyValueObservation] = [:]
    private var values: [UsageMenuKind: String] = [:]
    private let popover = NSPopover()
    private var presented: UsageMenuKind?
    private var samplingClient: String?
    private var driveRefresh: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: AppModel) {
        self.model = model
        super.init()
        // Own dismissal consistently, including clicks on the active status
        // item. AppKit's transient behavior can close on mouse-down and then
        // reopen from that same item's mouse-up action.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        trackReadings()
        model.openUsagePanel = { [weak self] kind in
            guard let self, let button = self.items[kind]?.button else { return }
            self.togglePanel(button)
        }
    }

    isolated deinit {
        driveRefresh?.cancel()
        stopMonitoringOutsideClicks()
        visibility.removeAll()
        popover.delegate = nil
        popover.close()
        stopSampling()
        popover.contentViewController = nil
        for (kind, item) in items {
            NSStatusBar.system.removeStatusItem(item)
            model.monitor.end(kind.backgroundClient)
        }
    }

    private func trackReadings() {
        withObservationTracking {
            // A status item's window follows the menu bar, not NSApp.appearance.
            // Set the popover's own appearance, including clearing it for System.
            popover.appearance = model.settings.appearance.nsAppearance
            for kind in UsageMenuKind.allCases.reversed() {
                let shown = model.settings[keyPath: kind.setting]
                if shown, items[kind] == nil { insert(kind) }
                if !shown, items[kind] != nil { remove(kind) }
                if shown { update(kind) }
            }
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.trackReadings() }
        }
    }

    private func insert(_ kind: UsageMenuKind) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if kind == .battery { item.length = 32 }
        items[kind] = item
        item.autosaveName = "CachePopUsage.\(kind.rawValue)"
        item.behavior = .removalAllowed
        item.isVisible = true
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("\(kind.rawValue)UsageMenuBarItem")
        }
        visibility[kind] = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false, let self else { return }
            Task { @MainActor in self.model.settings[keyPath: kind.setting] = false }
        }
        if kind == .drive {
            driveRefresh = Task { [weak self] in
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.model.refreshDisk()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
        model.monitor.begin(kind.backgroundClient)
    }

    private func remove(_ kind: UsageMenuKind) {
        if presented == kind { popover.performClose(nil) }
        visibility[kind] = nil
        if let item = items.removeValue(forKey: kind) { NSStatusBar.system.removeStatusItem(item) }
        values[kind] = nil
        if kind == .drive {
            driveRefresh?.cancel()
            driveRefresh = nil
        }
        model.monitor.end(kind.backgroundClient)
    }

    private func update(_ kind: UsageMenuKind) {
        guard let item = items[kind], let button = item.button else { return }
        let battery = model.monitor.snapshot?.battery
        let value: String
        switch kind {
        case .cpu: value = SystemMonitorViewModel.menuBarCPUUsage(model.monitor.snapshot) ?? "—"
        case .gpu: value = MonitorFormat.percent(model.monitor.snapshot?.gpus.first?.utilization)
        case .memory: value = SystemMonitorViewModel.menuBarMemoryUsage(model.monitor.snapshot) ?? "—"
        case .drive: value = SystemMonitorViewModel.menuBarSSDUsage(model.disk) ?? "—"
        case .battery: value = battery.map { "\($0.percent)%" } ?? "—"
        }
        let stateKey = kind == .battery ? "\(value)|\(battery?.isCharging ?? false)|\(battery?.isPluggedIn ?? false)" : value
        guard values[kind] != stateKey else { return }
        values[kind] = stateKey
        if kind == .battery {
            let state = battery.map { $0.isCharging ? "Charging" : $0.isPluggedIn ? "Power adapter" : "On battery" } ?? "Reading battery"
            button.image = BatteryMenuBarIcon.image(percent: battery?.percent, isCharging: battery?.isCharging ?? false)
            button.setAccessibilityLabel("Battery usage, \(value), \(state)")
            button.setAccessibilityValue(value)
            button.toolTip = "Battery: \(value) · \(state). Click for details."
        } else {
            button.image = UsageMenuBarLabel.image(title: kind.title, value: value)
            button.setAccessibilityLabel("\(kind.title) usage, \(value)")
            button.toolTip = "\(kind.title) usage: \(value). Click for details."
        }
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let kind = items.first(where: { $0.value.button === sender })?.key else { return }
        diagnose("toggle \(kind.rawValue) active=\(NSApp.isActive) visible=\(sender.window?.isVisible ?? false)")
        if presented == kind, popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.performClose(nil)
        stopSampling()
        presented = kind
        popover.contentViewController = NSHostingController(rootView:
            UsageMenuContent(model: model, kind: kind, onClose: { [weak self] in self?.popover.performClose(nil) })
        )
        popover.appearance = model.settings.appearance.nsAppearance
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        diagnose("show \(kind.rawValue) shown=\(popover.isShown)")
        if popover.isShown {
            samplingClient = kind.client
            model.monitor.begin(kind.client)
            if kind == .drive { model.refreshDisk() }
        }
        popover.contentViewController?.view.window?.makeKey()
        sender.highlight(true)
        update(kind)
        startMonitoringOutsideClicks()
    }

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.popover.performClose(nil)
                return nil
            }
            if !self.containsMenu(at: NSEvent.mouseLocation) { self.diagnose("close local outside"); self.popover.performClose(nil) }
            return event
        }
        // Transient popovers alone do not reliably dismiss from accessory apps.
        // A global mouse monitor covers clicks delivered to another app, without
        // intercepting the click or requiring keyboard/accessibility monitoring.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self, !self.containsMenu(at: NSEvent.mouseLocation) else { return }
            self.diagnose("close global outside")
            self.popover.performClose(nil)
        }
    }

    private func containsMenu(at point: NSPoint) -> Bool {
        if popover.contentViewController?.view.window?.frame.contains(point) == true { return true }
        // Status-item mouse events can be forwarded by the system menu bar host,
        // so use screen coordinates rather than depending on event.window.
        // Leave these clicks to togglePanel (including switching usage items).
        return items.values.contains { item in
            guard let button = item.button, let window = button.window else { return false }
            return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) {
        diagnose("did close \(presented?.rawValue ?? "none")")
        stopMonitoringOutsideClicks()
        stopSampling()
        // Release the hosted view and its sampling client when the panel closes,
        // rather than keeping an invisible CPU/process view alive until the next click.
        popover.contentViewController = nil
        let previous = presented
        presented = nil
        if let previous {
            items[previous]?.button?.highlight(false)
            update(previous)
        }
    }

    private func stopSampling() {
        guard let samplingClient else { return }
        self.samplingClient = nil
        model.monitor.end(samplingClient)
    }

    private func diagnose(_ value: @autoclosure () -> String) {
        #if DEBUG
        guard DemoMode.isUsageUITest, let path = ProcessInfo.processInfo.environment["CACHEPOP_POPUP_DIAGNOSTICS"] else { return }
        let data = Data("\(Date().ISO8601Format()) \(value())\n".utf8)
        if let file = FileHandle(forWritingAtPath: path) { defer { try? file.close() }; file.seekToEndOfFile(); file.write(data) }
        else { try? data.write(to: URL(fileURLWithPath: path)) }
        #endif
    }
}
