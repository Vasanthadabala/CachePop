import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CachePop

@Suite("Login Items switches")
struct LoginItemSwitchTests {
    @Test func parsesLaunchdOnOffRecord() {
        let output = """
        	disabled services = {
        		"com.google.keystone.daemon" => enabled
        		"com.example.helper" => disabled
        		"com.old.style" => true
        		"com.old.other" => false
        	}
        """
        #expect(LaunchOverrides.parse(output) == [
            "com.google.keystone.daemon": false,
            "com.example.helper": true,
            "com.old.style": true,
            "com.old.other": false
        ])
    }

    @Test func parsesOpenAtLoginList() {
        let output = "Dropbox\t/Applications/Dropbox.app/\nBroken\tmissing value\nRectangle\t/Applications/Rectangle.app\n"
        #expect(OpenAtLoginApp.parse(output) == [
            OpenAtLoginApp(name: "Dropbox", path: "/Applications/Dropbox.app"),
            OpenAtLoginApp(name: "Rectangle", path: "/Applications/Rectangle.app")
        ])
    }

    /// Reading the list goes through `osascript`, so a slow System Events never holds the window.
    @Test func openAtLoginAppsAreReadThroughOsascript() async throws {
        let runner = FakeCommandRunner { _ in
            CommandOutput(status: 0, stdout: "Dropbox\t/Applications/Dropbox.app/\n", stderr: "")
        }
        var control = LiveStartupControl()
        control.runner = runner
        #expect(try await control.openAtLoginApps() == [OpenAtLoginApp(name: "Dropbox", path: "/Applications/Dropbox.app")])
        #expect(runner.calls.map(\.executable.path) == ["/usr/bin/osascript"])
    }

    @Test func osascriptErrorsBecomeLoginItemErrors() async {
        let denied = "36:120: execution error: Not authorized to send Apple events to System Events. (-1743)\n"
        #expect(StartupControlError.fromOsascript(denied) == .notAllowed)
        #expect(StartupControlError.fromOsascript("0:5: execution error: User canceled. (-128)") == .cancelled)
        #expect(StartupControlError.fromOsascript("1:2: execution error: System Events got an error: Oops. (-1728)")
                == .failed("System Events got an error: Oops."))

        var control = LiveStartupControl()
        control.runner = FakeCommandRunner { _ in CommandOutput(status: 1, stdout: "", stderr: denied) }
        await #expect(throws: StartupControlError.notAllowed) { try await control.openAtLoginApps() }
    }

    /// Icons are drawn once as a small bitmap at twice the shown size, not the 1024 px original.
    @Test func iconsAreSmallBitmaps() throws {
        let icon = IconCache.thumbnail(of: NSWorkspace.shared.icon(for: .applicationBundle), points: 30)
        #expect(icon.size == NSSize(width: 30, height: 30))
        let rep = try #require(icon.representations.first)
        #expect(icon.representations.count == 1)
        #expect(rep.pixelsWide == 60 && rep.pixelsHigh == 60)
        #expect(IconCache.icon(forFile: "/no/such/App.app", points: 30, fallback: .applicationBundle).size.width == 30)
    }

    @Test func agentStateFollowsLaunchdThenThePlist() throws {
        let fixture = try Fixture()
        let folder = try fixture.dir("Library/LaunchAgents")
        func write(_ name: String, _ info: NSDictionary) {
            info.write(to: folder.appendingPathComponent("\(name).plist"), atomically: true)
        }
        write("com.example.on", ["Label": "com.example.on", "Program": "/usr/local/bin/on"])
        write("com.example.off", ["Label": "com.example.off", "Program": "/usr/local/bin/off"])
        write("com.example.plistoff", ["Label": "com.example.plistoff", "Program": "/bin/x", "Disabled": true])
        write("com.example.revived", ["Label": "com.example.revived", "Program": "/bin/y", "Disabled": true])
        write("com.example.empty", [:])

        let items = LoginItemsScanner.launchItems(
            in: folder, kind: .userAgent,
            overrides: ["com.example.off": true, "com.example.revived": false]
        )
        let state = Dictionary(uniqueKeysWithValues: items.map { ($0.path.components(separatedBy: "/").last ?? "", $0.isOn) })
        #expect(state["com.example.on.plist"] == true)
        #expect(state["com.example.off.plist"] == false)
        #expect(state["com.example.plistoff.plist"] == false)
        #expect(state["com.example.revived.plist"] == true)

        // An empty file runs nothing, so there's nothing to switch and it isn't listed.
        let empty = try #require(items.first { $0.path.hasSuffix("com.example.empty.plist") })
        #expect(empty.label == nil && !empty.canToggle && !empty.isOn)
        #expect(empty.role == .empty && !empty.isListed)
    }

    /// Plist shapes taken from a real Mac (CCleaner, Cloudflare WARP, Google, Chrome Remote Desktop).
    @Test func listsOnlyWhatStartsOnItsOwn() {
        func role(_ info: [String: Any], _ kind: LoginItem.Kind, _ program: String) -> LoginItem.Role {
            LoginItemsScanner.role(of: info, kind: kind, program: program)
        }
        let app = "/Applications/Example.app/Contents/MacOS/example"
        // Starts by itself: worth a switch.
        #expect(role(["RunAtLoad": true], .sharedAgent, "/Library/PrivilegedHelperTools/Host.app/Contents/MacOS/host") == .startsOnItsOwn)
        #expect(role(["StartInterval": 3600], .daemon, "/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/MacOS/GoogleUpdater") == .startsOnItsOwn)
        #expect(role(["KeepAlive": true, "MachServices": ["x": true]], .sharedAgent, app) == .startsOnItsOwn)
        #expect(role(["KeepAlive": false, "StartInterval": 14400], .daemon, app) == .startsOnItsOwn)
        // Only when its app asks: hidden.
        #expect(role(["KeepAlive": false, "MachServices": ["x": true]], .daemon, app) == .onDemand)
        #expect(role(["MachServices": ["x": true]], .daemon, "/Library/PrivilegedHelperTools/Host.app/Contents/MacOS/broker") == .onDemand)
        #expect(role(["RunAtLoad": false, "KeepAlive": false], .daemon, app) == .onDemand)
        // The app's own engine, kept running so the app works: hidden.
        #expect(role(["RunAtLoad": true, "KeepAlive": true], .daemon, "/Applications/Cloudflare WARP.app/Contents/Resources/CloudflareWARP") == .appService)
        // A standalone daemon kept alive outside any app is still listed.
        #expect(role(["KeepAlive": true], .daemon, "/usr/local/bin/tool") == .startsOnItsOwn)
    }

    @Test func onlyPlainLabelsAndPathsReachTheShell() {
        #expect(LiveStartupControl.isSafeLabel("com.cloudflare.1dot1dot1dot1.macos.warp.daemon"))
        #expect(!LiveStartupControl.isSafeLabel("com.evil; rm -rf ~"))
        #expect(!LiveStartupControl.isSafeLabel(""))
        #expect(LiveStartupControl.isSafePath("/Library/LaunchDaemons/com.example.daemon.plist"))
        #expect(LiveStartupControl.isSafePath("/Applications/Cloudflare WARP.app"))
        #expect(!LiveStartupControl.isSafePath("/Applications/It's.app"))
        #expect(!LiveStartupControl.isSafePath("/Applications/\"x\".app"))
        #expect(!LiveStartupControl.isSafePath("relative/path"))
    }

    @MainActor
    @Test func switchingAnAgentAndAnAppOffAndBackOn() async throws {
        let fixture = try Fixture()
        let folder = try fixture.dir("Library/LaunchAgents")
        let agentInfo: NSDictionary = ["Label": "com.example.sync", "Program": "/Applications/Sync.app/Contents/MacOS/sync", "RunAtLoad": true]
        agentInfo.write(to: folder.appendingPathComponent("com.example.sync.plist"), atomically: true)
        let appPath = try fixture.dir("Applications/Notes Helper.app").path

        let control = DemoStartupControl(apps: [OpenAtLoginApp(name: "Notes Helper", path: appPath)])
        let model = LoginItemsViewModel(control: control, home: fixture.home)
        var remembered: [String] = []
        model.rememberedOffApps = { remembered }
        model.setRememberedOffApps = { remembered = $0 }

        model.scan()
        try await waitFor { model.hasScanned }
        let agent = try #require(model.agents.first { $0.label == "com.example.sync" })
        let app = try #require(model.apps.first { $0.path == appPath })
        #expect(agent.isOn && app.isOn)

        model.set(agent, on: false)
        model.set(app, on: false)
        try await waitFor { model.busyIDs.isEmpty }
        #expect(await control.overrides().gui["com.example.sync"] == true)
        #expect(remembered == [appPath])

        // After a rescan both still show, switched off.
        model.scan()
        try await waitFor { !model.isScanning }
        #expect(model.agents.first { $0.label == "com.example.sync" }?.isOn == false)
        #expect(model.apps.first { $0.path == appPath }?.isOn == false)

        let offApp = try #require(model.apps.first { $0.path == appPath })
        model.set(offApp, on: true)
        try await waitFor { model.busyIDs.isEmpty }
        #expect(remembered.isEmpty)
        #expect(model.apps.first { $0.path == appPath }?.isOn == true)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
