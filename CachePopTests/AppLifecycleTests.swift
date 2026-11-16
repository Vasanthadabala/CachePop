import AppKit
import Testing
@testable import CachePop

@Suite("Menu bar lifecycle")
struct AppLifecycleTests {
    @MainActor
    @Test func closingTheWindowKeepsAnActiveRecordingAlive() throws {
        let fixture = try Fixture()
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false)
        settings.showMenuBarItem = false
        let model = AppModel(environment: fixture.environment(), settings: settings,
                             history: CleanHistory(inMemory: true), notifications: SilentNotifications(),
                             fanController: InertFanController(), startupControl: DemoStartupControl())
        let previous = AppDelegate.model
        defer { AppDelegate.model = previous; model.monitor.stopRecording() }
        AppDelegate.model = model
        model.monitor.startRecording()
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        model.monitor.stopRecording()
        #expect(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

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

        let readings: [ReferenceWritableKeyPath<AppSettings, Bool>] = [
            \.menuBarShowsCPUUsage, \.menuBarShowsMemoryUsage, \.menuBarShowsSSDUsage,
            \.menuBarShowsTemperature, \.menuBarShowsFanSpeed
        ]
        for enabled in readings {
            for key in readings { settings[keyPath: key] = key == enabled }
            model.keepRunningInMenuBar()
            #expect(NSApp.activationPolicy() == .accessory)
            #expect(!model.isMainWindowContentActive)
            #expect(settings[keyPath: enabled])

            model.show(.systemMonitor)
            #expect(NSApp.activationPolicy() == .regular)
            #expect(model.isMainWindowContentActive)
            #expect(model.section == .systemMonitor)
        }
        #expect(windowOpened == readings.count)
    }

    @MainActor
    @Test func explicitQuitIsAllowedWithReadingsEnabled() throws {
        let fixture = try Fixture()
        let suite = "CachePop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: try #require(UserDefaults(suiteName: suite)), canChangeLoginItem: false)
        settings.menuBarShowsCPUUsage = true
        settings.menuBarShowsMemoryUsage = true
        settings.menuBarShowsSSDUsage = true
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
