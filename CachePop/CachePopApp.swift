//
//  CachePopApp.swift
//  CachePop
//
//  Created by Vasanth on 13/05/26.
//

import AppKit
import SwiftUI
import UserNotifications

@main
struct CachePopApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = Self.makeModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window("CachePop", id: Self.mainWindowID) {
            RootView(model: model)
                .tint(AppTheme.Colors.accent)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { AppCommands(model: model) }

        MenuBarExtra(isInserted: cachePopItemShown) {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        // The temperature and the fan speed, each in a menu bar item of its own. Both open the
        // same panel as CachePop's icon.
        MenuBarExtra(isInserted: setting(\.menuBarShowsTemperature)) {
            MenuBarContent(model: model)
        } label: {
            MenuBarReadingLabel(model: model, reading: .temperature)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: setting(\.menuBarShowsFanSpeed)) {
            MenuBarContent(model: model)
        } label: {
            MenuBarReadingLabel(model: model, reading: .fanSpeed)
        }
        .menuBarExtraStyle(.window)
    }

    /// A menu bar item's place in Settings. Removing the item from the menu bar (⌘-drag) turns
    /// its setting off.
    private func setting(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
    }

    /// CachePop's own item: it stays while CachePop opens at login, starting hidden.
    private var cachePopItemShown: Binding<Bool> {
        Binding(get: { model.settings.showMenuBarItem }, set: { isShown in
            if isShown || !model.settings.menuBarItemIsRequired { model.settings.showMenuBarItem = isShown }
        })
    }

    @MainActor
    private static func makeModel() -> AppModel {
        #if DEBUG
        if let environment = DemoMode.environmentIfRequested() {
            let fans = DemoFans()
            return AppModel(
                environment: environment,
                settings: DemoMode.settings(),
                history: DemoMode.history(),
                notifications: SilentNotifications(),
                fanController: DemoFanController(fans: fans),
                fanSource: { fans.read() },
                startupControl: DemoMode.startupControl
            )
        }
        #endif
        if AppDelegate.isRunningTests {
            // The test host never touches the real preferences or history.
            let defaults = UserDefaults(suiteName: "CachePop.tests") ?? .standard
            return AppModel(
                settings: AppSettings(defaults: defaults, canChangeLoginItem: false),
                history: CleanHistory(inMemory: true),
                notifications: SilentNotifications(),
                fanController: InertFanController(),
                startupControl: DemoStartupControl()
            )
        }
        return AppModel()
    }
}

/// Keeps CachePop running for its menu bar items, starts it hidden at login, and opens Clean Up
/// from a low-space alert.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var model: AppModel?
    /// True while a login launch closes its window: CachePop stays running, menu bar item or not.
    private var isStartingHidden = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.isRunningTests {
            UNUserNotificationCenter.current().delegate = self
            Self.model?.settings.appearance.apply()
            // Turned on at login before the menu bar item was required: bring it back.
            if let settings = Self.model?.settings, settings.menuBarItemIsRequired, !settings.showMenuBarItem {
                settings.showMenuBarItem = true
            }
            if Self.wasLaunchedAtLogin {
                startHidden()
            }
        }
        Self.model?.startMonitoring()
    }

    /// macOS opened CachePop as a login item, rather than someone opening it. Read while the
    /// launch's "open application" event is still the current one (during launch only).
    private static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Opened at login: start hidden, with no window, just the menu bar items and alerts. Open
    /// it from the menu bar or the Dock. The window can arrive a moment after launch, so keep
    /// closing it for the first second.
    private func startHidden() {
        Self.model?.endLaunch(reduceMotion: true)
        isStartingHidden = true
        Task { @MainActor in
            for _ in 0..<10 {
                for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                    window.close()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            isStartingHidden = false
        }
    }

    /// Fans on a fixed speed go back to macOS before CachePop quits. (The helper also does
    /// this on its own when CachePop disconnects.)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let fanControl = Self.model?.fanControl, fanControl.isCustom else { return .terminateNow }
        // Whichever comes first: the fans are released, or three seconds pass.
        let reply = ReplyOnce { sender.reply(toApplicationShouldTerminate: true) }
        Task { @MainActor in
            await fanControl.setAutomatic()
            reply.send()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            reply.send()
        }
        return .terminateLater
    }

    /// With a menu bar item showing, closing the window leaves CachePop running for alerts; so
    /// does closing it to start hidden at login.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isStartingHidden && !(Self.model?.settings.showsAnyMenuBarItem ?? false)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in AppDelegate.model?.show(.cleanUp) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Runs its action once, however many times it's asked.
@MainActor
final class ReplyOnce {
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func send() {
        action?()
        action = nil
    }
}
