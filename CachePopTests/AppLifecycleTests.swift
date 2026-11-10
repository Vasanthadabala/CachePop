import AppKit
import Testing
@testable import CachePop

@Suite("Menu bar lifecycle")
struct AppLifecycleTests {
    @MainActor
    @Test func menuBarOnlyModeKeepsReadingsAndReopeningRestoresTheApp() throws {
        let fixture = try Fixture()
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        settings.showMenuBarItem = false
        let model = AppModel(environment: fixture.environment(), settings: settings,
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: DemoStartupControl())
        var windowOpened = 0
        model.openMainWindow = { windowOpened += 1 }
        let originalPolicy = NSApp.activationPolicy()
        let wasHidden = NSApp.isHidden
        defer {
            NSApp.setActivationPolicy(originalPolicy)
            if wasHidden { NSApp.hide(nil) } else { NSApp.unhide(nil) }
        }

        for (temperature, fan) in [(true, false), (false, true), (true, true)] {
            settings.menuBarShowsTemperature = temperature
            settings.menuBarShowsFanSpeed = fan
            model.keepRunningInMenuBar()
            #expect(NSApp.activationPolicy() == .accessory)
            #expect(settings.menuBarShowsTemperature == temperature)
            #expect(settings.menuBarShowsFanSpeed == fan)

            model.show(.systemMonitor)
            #expect(NSApp.activationPolicy() == .regular)
            #expect(model.section == .systemMonitor)
        }
        #expect(windowOpened == 3)
    }

    @MainActor
    @Test func explicitQuitIsAllowedWithReadingsEnabled() throws {
        let fixture = try Fixture()
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false)
        settings.menuBarShowsTemperature = true
        settings.menuBarShowsFanSpeed = true
        let model = AppModel(environment: fixture.environment(), settings: settings,
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: DemoStartupControl())
        let previousModel = AppDelegate.model
        defer { AppDelegate.model = previousModel }
        AppDelegate.model = model

        // The Dock, an explicit Quit menu item, and system shutdown all reach this delegate.
        #expect(AppDelegate().applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }
}
