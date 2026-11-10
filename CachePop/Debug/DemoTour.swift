#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: steps through the main screens and saves each as a PNG, then quits.
///
/// `-CachePopTour <folder>` runs it. With `-CachePopDemo` it cleans the fixture end to end;
/// add `-CachePopTourReadOnly` to scan and capture without cleaning (safe on the real Mac).
/// It renders the app's own windows, so it needs no Screen Recording permission.
@MainActor
enum DemoTour {
    static func runIfRequested(model: AppModel) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CachePopTour"), index + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        await run(model: model, folder: folder, readOnly: arguments.contains("-CachePopTourReadOnly"))
        NSApp.terminate(nil)
    }

    private static func run(model: AppModel, folder: URL, readOnly: Bool) async {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate()
        mainWindow?.setFrame(NSRect(x: 80, y: 80, width: 1180, height: 860), display: true)
        await pause(0.2)
        snap("00-launch-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(0.15)
        snap("00-launch", folder)
        await pause(0.55)
        snap("00-launch-spin", folder)
        await waitUntil(timeout: 10) { !model.isLaunching }
        await pause(1)
        snap("01-clean-up-start", folder)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(0.8)
        snap("01-clean-up-start-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(0.5)

        model.isShowingHistory = true
        await pause(1)
        snapSheet("01b-history", folder)
        model.isShowingHistory = false
        await pause(0.6)

        model.cleanUp.scan()
        await pause(0.6)
        snap("02-clean-up-scanning", folder)
        await waitUntil(timeout: 600) { model.cleanUp.phase == .review }
        await pause(1)
        snap("03-clean-up-review", folder)

        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(1)
        snap("04-clean-up-review-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(0.8)

        if !readOnly {
            let items = model.cleanUp.result.allItems
            if let iphone = items.first(where: { $0.id.hasPrefix("simulators.device.") && !$0.isBlocked }) {
                model.cleanUp.choose(iphone.action(withID: "erase"), for: iphone)
                model.cleanUp.setSelected(iphone, true)
            }
            if let installers = items.first(where: { $0.id == "general.installers" }) {
                model.cleanUp.setSelected(installers, true)
            }
            await pause(0.5)
            model.cleanUp.requestClean()
            await pause(1.2)
            snapSheet("05-clean-up-confirm", folder)

            model.cleanUp.confirmClean()
            await waitUntil(timeout: 300) { model.cleanUp.phase == .done }
            await pause(2)
            snap("06-clean-up-done", folder)
            model.cleanUp.putBack()
            await pause(0.8)
            snap("06b-put-back", folder)
        }

        model.section = .largeFiles
        await pause(0.8)
        snap("07a-large-files-start", folder)
        if readOnly {
            // Scanning Desktop, Documents and Downloads on a real Mac raises privacy prompts.
            snap("07-large-files-start", folder)
        } else {
            model.largeFiles.scan()
            await waitUntil(timeout: 600) { model.largeFiles.phase == .results }
            await pause(1)
            snap("07-large-files", folder)
            model.largeFiles.kindFilter = .videos
            await pause(0.6)
            snap("07b-large-files-filter", folder)
            model.largeFiles.kindFilter = nil
            model.largeFiles.tab = .duplicates
            model.largeFiles.selectExtraCopies()
            await pause(0.8)
            snap("08-duplicates", folder)
        }

        model.section = .apps
        await waitUntil(timeout: 300) { model.apps.hasScanned }
        await waitUntil(timeout: 120) { !model.apps.isMeasuringLibraries }
        await pause(1.5)
        snap("09-applications", folder)

        model.section = .loginItems
        await waitUntil(timeout: 120) { model.loginItems.hasScanned }
        await pause(1)
        snap("10-login-items", folder)
        model.loginItems.scrollToApps = true
        await pause(1)
        snap("10b-login-items-apps", folder)

        model.section = .diskUsage
        await pause(0.8)
        snap("12a-disk-usage-start", folder)
        model.diskUsage.start()
        await waitUntil(timeout: 300) { model.diskUsage.phase == .ready }
        await pause(1.2)
        snap("12-disk-usage", folder)
        if let library = model.diskUsage.overviewEntries.first(where: { $0.name == "Library" }) {
            model.diskUsage.open(library)
            await waitUntil(timeout: 120) { !model.diskUsage.isMeasuringCurrent }
            await pause(1.2)
            snap("13-disk-usage-folder", folder)
        }

        model.section = .systemMonitor
        await waitUntil(timeout: 30) { !model.monitor.processes.isEmpty }
        await pause(8)
        snap("19-system-monitor", folder)
        model.monitor.scrollToProcesses = true
        await pause(1.2)
        snap("19b-system-monitor-processes", folder)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(2.5)
        snap("20-system-monitor-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)

        // Fan control, with demo mode's two pretend fans. Never on a real Mac: it would
        // install the root helper.
        if DemoMode.isRequested, let fans = model.monitor.snapshot?.fans, !fans.isEmpty {
            model.monitor.scrollToProcesses = false
            model.section = .cleanUp
            await pause(0.3)
            model.section = .systemMonitor
            await pause(1.5)
            snap("21-fans-off", folder)
            model.fanControl.install()
            model.fanControl.targets = [0: 3_600, 1: 4_200]
            await model.fanControl.apply(fans)
            await pause(4.5)
            snap("22-fans-custom", folder)
            await model.fanControl.setAutomatic()
        }

        // Section switch and reset in the same instant: the case that used to render blank.
        model.section = .cleanUp
        model.cleanUp.startOver()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(1)
        snap("11-clean-up-start-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        await pause(0.5)

        await snapMenuBarPanel("18-menu-bar", folder, MenuBarContent(model: model))
        await snapMenuBarPanel("18b-menu-bar-temperatures", folder, TemperatureMenuContent(model: model))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await pause(0.3)
        await snapMenuBarPanel("18c-menu-bar-temperatures-dark", folder, TemperatureMenuContent(model: model))
        NSApp.appearance = NSAppearance(named: .aqua)

        model.section = .settings
        for (index, tab) in SettingsTab.allCases.enumerated() {
            model.settings.selectedTab = tab
            await pause(1)
            snap("\(14 + index)-settings-\(tab.rawValue)", folder)
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model.settings.selectedTab = .general
        await pause(1)
        snap("14b-settings-general-dark", folder)
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.appearance = nil
    }

    /// A menu bar panel, hosted in a plain window so it can be captured.
    private static func snapMenuBarPanel(_ name: String, _ folder: URL, _ panel: some View) async {
        let host = NSHostingView(rootView: panel)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 1300, y: 300), size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        await pause(0.8)
        save(window, to: folder.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    // MARK: Helpers

    private static var mainWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.sheetParent == nil && $0.canBecomeMain
                && $0.identifier?.rawValue.contains("Settings") != true
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func waitUntil(timeout: Double, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        // Once cancelled (the window closed), `pause` returns at once: stop rather than spin.
        while !condition(), Date() < deadline, !Task.isCancelled {
            await pause(0.2)
        }
    }

    private static func snap(_ name: String, _ folder: URL) {
        guard let window = mainWindow else { return }
        save(window, to: folder.appendingPathComponent("\(name).png"))
    }

    private static func snapSheet(_ name: String, _ folder: URL) {
        guard let sheet = mainWindow?.attachedSheet else {
            snap(name, folder)
            return
        }
        save(sheet, to: folder.appendingPathComponent("\(name).png"))
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// An app may capture its own windows without Screen Recording permission. The symbol is
    /// looked up at runtime because the SDK no longer exposes it to Swift.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: WindowImageFunction.self)
        let includingWindow: UInt32 = 1 << 3
        let ignoreFramingAndBestResolution: UInt32 = (1 << 0) | (1 << 3)
        return create(.null, includingWindow, UInt32(window.windowNumber), ignoreFramingAndBestResolution)?.takeRetainedValue()
    }

    private static func save(_ window: NSWindow, to url: URL) {
        if let image = windowImage(window), image.width > 10 {
            let representation = NSBitmapImageRep(cgImage: image)
            try? representation.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: representation)
        try? representation.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
