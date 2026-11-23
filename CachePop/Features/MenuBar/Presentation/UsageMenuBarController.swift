import AppKit
import Observation
import SwiftUI

/// Each component owns a native button and accessibility target; all share one focused popover.
@MainActor
final class UsageMenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private var items: [StatusMenuKind: NSStatusItem] = [:]
    private var visibility: [StatusMenuKind: NSKeyValueObservation] = [:]
    private var values: [StatusMenuKind: String] = [:]
    private let popover = NSPopover()
    private var presented: StatusMenuKind?
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
        model.openMenuBarPanel = { [weak self] kind in
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
            if let client = kind.backgroundClient { model.monitor.end(client) }
        }
    }

    private func trackReadings() {
        withObservationTracking {
            // A status item's window follows the menu bar, not NSApp.appearance.
            // Set the popover's own appearance, including clearing it for System.
            popover.appearance = model.settings.appearance.nsAppearance
            for kind in StatusMenuKind.all.reversed() {
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

    private func insert(_ kind: StatusMenuKind) {
        let item = NSStatusBar.system.statusItem(withLength: MenuBarItemLayout.nativeLength(for: kind.width))
        items[kind] = item
        item.autosaveName = kind == .cachePop ? "CachePop" : kind == .temperature ? "CachePopTemperature" : "CachePopUsage.\(kind.rawValue)"
        item.behavior = .removalAllowed
        item.isVisible = true
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier(kind.accessibilityIdentifier)
        }
        visibility[kind] = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false, let self else { return }
            Task { @MainActor in
                if kind == .cachePop, self.model.settings.menuBarItemIsRequired {
                    self.items[kind]?.isVisible = true
                } else { self.model.settings[keyPath: kind.setting] = false }
            }
        }
        if kind == .usage(.drive) {
            driveRefresh = Task { [weak self] in
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.model.refreshDisk()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
        if let client = kind.backgroundClient { model.monitor.begin(client) }
    }

    private func remove(_ kind: StatusMenuKind) {
        if presented == kind { popover.performClose(nil) }
        visibility[kind] = nil
        if let item = items.removeValue(forKey: kind) { NSStatusBar.system.removeStatusItem(item) }
        values[kind] = nil
        if kind == .usage(.drive) {
            driveRefresh?.cancel()
            driveRefresh = nil
        }
        if let client = kind.backgroundClient { model.monitor.end(client) }
    }

    private func update(_ kind: StatusMenuKind) {
        guard let button = items[kind]?.button else { return }
        switch kind {
        case .cachePop:
            if values[kind] == nil { button.image = MenuBarLabel.glyph; values[kind] = "CachePop" }
            button.setAccessibilityLabel("CachePop")
            button.toolTip = "CachePop. Click to open."
        case .temperature:
            let value = SystemMonitorViewModel.menuBarTemperature(model.monitor.snapshot) ?? "—"
            if values[kind] != value {
                values[kind] = value
                button.image = MenuBarItemLayout.image(width: kind.width) { TemperatureStatusReading(value: value) }
            }
            button.setAccessibilityLabel("Chip temperature, \(value)")
            button.setAccessibilityValue(value)
            button.toolTip = "Temperature: \(value). Click for details."
        case .usage(let usage): updateUsage(usage)
        }
    }

    private func updateUsage(_ kind: UsageMenuKind) {
        guard let button = items[.usage(kind)]?.button else { return }
        let battery = model.monitor.snapshot?.battery
        let value: String
        switch kind {
        case .cpu: value = SystemMonitorViewModel.menuBarCPUUsage(model.monitor.snapshot) ?? "—"
        case .gpu: value = MonitorFormat.percent(model.monitor.snapshot?.gpus.first?.utilization)
        case .memory: value = SystemMonitorViewModel.menuBarMemoryUsage(model.monitor.snapshot) ?? "—"
        case .drive: value = SystemMonitorViewModel.menuBarSSDUsage(model.disk) ?? "—"
        case .battery: value = battery.map { "\($0.percent)%" } ?? "—"
        case .sensors: value = "Sensors"
        case .network:
            if let snapshot = model.monitor.snapshot, snapshot.hasNetworkReadings {
                value = "↑ \(SystemMonitorViewModel.rate(snapshot.network.outPerSecond))|↓ \(SystemMonitorViewModel.rate(snapshot.network.inPerSecond))"
            } else { value = "↑ —|↓ —" }
        }
        let stateKey = kind == .battery ? "\(value)|\(battery?.isCharging ?? false)|\(battery?.isPluggedIn ?? false)" : value
        guard values[.usage(kind)] != stateKey else { return }
        values[.usage(kind)] = stateKey
        if kind == .battery {
            let state = battery.map { $0.isCharging ? "Charging" : $0.isPluggedIn ? "Power adapter" : "On battery" } ?? "Reading battery"
            button.image = HardwareMenuBarLabel.batteryImage(
                percent: battery?.percent,
                isCharging: battery?.isCharging ?? false,
                isPluggedIn: battery?.isPluggedIn ?? false
            )
            button.setAccessibilityLabel("Battery usage, \(value), \(state)")
            button.setAccessibilityValue(value)
            button.toolTip = "Battery: \(value) · \(state). Click for details."
        } else if kind == .sensors {
            button.image = HardwareMenuBarLabel.sensorsImage()
            button.setAccessibilityLabel("Sensors")
            button.toolTip = "Sensors. Click for temperatures, fan speeds and electrical readings."
        } else if kind == .network {
            let lines = value.components(separatedBy: "|")
            button.image = HardwareMenuBarLabel.networkImage(upload: lines[0], download: lines[1])
            button.setAccessibilityLabel("Network traffic, upload \(lines[0]), download \(lines[1])")
            button.setAccessibilityValue(value.replacingOccurrences(of: "|", with: ", "))
            button.toolTip = "Network traffic · \(lines[0]) · \(lines[1]). Click for details."
        } else {
            button.image = UsageMenuBarLabel.image(title: kind.title, value: value, width: StatusMenuKind.usage(kind).width)
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
        let availableHeight = (sender.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        popover.contentViewController = NSHostingController(rootView: panel(kind, availableHeight: availableHeight - 20))
        popover.appearance = model.settings.appearance.nsAppearance
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        if kind == .usage(.sensors), let screen = sender.window?.screen ?? NSScreen.main {
            // A keyboard-opened item can have an offscreen proxy in a crowded menu bar.
            // Keep the enlarged panel and its fixed footer inside the anchor's display.
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
            if let window = popover.contentViewController?.view.window {
                let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                let origin = NSPoint(x: min(max(window.frame.minX, visible.minX), visible.maxX - window.frame.width),
                                     y: min(max(window.frame.minY, visible.minY), visible.maxY - window.frame.height))
                window.setFrameOrigin(origin)
            }
        }
        diagnose("show \(kind.rawValue) shown=\(popover.isShown)")
        if popover.isShown {
            samplingClient = kind.client
            model.monitor.begin(kind.client)
            if kind == .usage(.drive) { model.refreshDisk() }
        }
        popover.contentViewController?.view.window?.makeKey()
        sender.highlight(true)
        update(kind)
        startMonitoringOutsideClicks()
    }

    @ViewBuilder private func panel(_ kind: StatusMenuKind, availableHeight: CGFloat) -> some View {
        switch kind {
        case .cachePop:
            MenuBarContent(model: model, onClose: { [weak self] in self?.popover.performClose(nil) })
        case .temperature:
            TemperatureMenuContent(model: model, onClose: { [weak self] in self?.popover.performClose(nil) })
        case .usage(let usage):
            UsageMenuContent(model: model, kind: usage, onClose: { [weak self] in self?.popover.performClose(nil) },
                             availableHeight: availableHeight)
        }
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
