import XCTest

final class UsageMenuUITests: XCTestCase {
    @MainActor
    func testCPUProcessesLoadWithTheMainWindowClosed() throws { try verifyMenuBarOnlyProcesses("cpu", prefix: "CPU usage") }

    @MainActor
    func testMemoryProcessesLoadWithTheMainWindowClosed() throws { try verifyMenuBarOnlyProcesses("memory", prefix: "Memory usage") }

    @MainActor
    func testGPUPopupAndMonitorNavigation() throws { try verifyHardwarePopup("gpu", title: "GPU usage", page: "GPU") }

    @MainActor
    func testBatteryPopupAndMonitorNavigation() throws { try verifyHardwarePopup("battery", title: "Battery usage", page: "Battery") }

    @MainActor
    private func verifyHardwarePopup(_ kind: String, title: String, page: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let diagnosticPath = NSTemporaryDirectory() + "CachePop-popup-\(UUID().uuidString).log"
        app.launchEnvironment["CACHEPOP_POPUP_DIAGNOSTICS"] = diagnosticPath
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-hardware-popup-%p.profraw"
        app.launchArguments = ["-CachePopDemo", "-CachePopUsageUITest", "-CachePopUsageMenu=\(kind)", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["main"].waitForNonExistence(timeout: 5))
        let item = app.menuBars.statusItems.matching(identifier: "\(kind)UsageMenuBarItem").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        // Keyboard access remains available when a menu manager hides the status icon.
        app.typeKey(kind == "gpu" ? "g" : "b", modifierFlags: [.command, .control])
        let opened = app.staticTexts["\(kind)MenuTitle"].waitForExistence(timeout: 5)
        let diagnostics = (try? String(contentsOfFile: diagnosticPath, encoding: .utf8)) ?? "No button action recorded."
        if !opened { capture("\(page) popup click failure") }
        XCTAssertTrue(opened, diagnostics + "\n" + app.debugDescription)
        if kind == "gpu" { XCTAssertTrue(app.staticTexts["Renderer"].exists) }
        else { XCTAssertTrue(app.staticTexts["Maximum capacity"].exists) }
        capture("\(page) popup")
        app.buttons["System Monitor"].click()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
        let pages = app.descendants(matching: .any).matching(identifier: "monitorPages").firstMatch
        let selected = pages.descendants(matching: .radioButton).matching(identifier: page).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), app.debugDescription)
        // AppKit radio buttons expose their selection through AXValue; isSelected
        // is not populated consistently for segmented SwiftUI pickers on macOS.
        XCTAssertEqual((selected.value as? NSNumber)?.intValue, 1, "The popup should open its own module.\n\(app.debugDescription)")
        if kind == "gpu" { XCTAssertTrue(app.descendants(matching: .any)["gpuMonitorCard"].firstMatch.exists) }
        else { XCTAssertTrue(app.staticTexts["Battery power"].exists) }
        capture("\(page) popup navigation")
    }

    @MainActor
    private func verifyMenuBarOnlyProcesses(_ kind: String, prefix: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-menu-processes-%p.profraw"
        app.launchArguments = ["-CachePopDemo", "-CachePopUsageUITest", "-CachePopUsageMenu=\(kind)", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        // Restore the window through the app's normal command if macOS retained
        // a menu-bar-only launch from the preceding test.
        app.typeKey(",", modifierFlags: .command)
        let main = app.windows["main"]
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(main.waitForNonExistence(timeout: 5))
        let item = app.menuBars.statusItems.matching(NSPredicate(format: "title BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        app.typeKey(kind == "cpu" ? "c" : "m", modifierFlags: [.command, .control])
        let opened = app.staticTexts["\(kind)MenuTitle"].waitForExistence(timeout: 5)
        if !opened { capture("\(prefix) · popup click diagnostic") }
        XCTAssertTrue(opened, app.debugDescription)
        let process = app.descendants(matching: .any).matching(identifier: "usageProcess0").firstMatch
        XCTAssertTrue(process.exists, "Processes should already be collected before the first popup opens.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Reading processes…"].exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["\(kind)MenuTitle"].waitForNonExistence(timeout: 5))
        // Exceed the old ten-second cache lifetime; collection must continue with no popup.
        Thread.sleep(forTimeInterval: 12)
        app.typeKey(kind == "cpu" ? "c" : "m", modifierFlags: [.command, .control])
        XCTAssertTrue(process.exists, "Background collection should keep rows ready after a long-closed popup.")
        XCTAssertFalse(app.staticTexts["Reading processes…"].exists)
        capture("\(prefix) · main window closed")
    }

    @MainActor
    func testNativeMenuRestoresMainWindowAfterOrdinaryRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-native-relaunch-%p.profraw"
        app.launchArguments = ["-CachePopDemo", "-CachePopFanUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["main"].waitForNonExistence(timeout: 5))
        app.terminate()

        // Exercise normal saved-window restoration, without the ignore-state override.
        app.launchArguments = ["-CachePopDemo", "-CachePopFanUITest"]
        app.launch()
        defer { app.terminate() }
        let fan = app.menuBars.statusItems.matching(NSPredicate(format: "label BEGINSWITH 'Fan speed' OR title BEGINSWITH 'Fan speed'")).firstMatch
        XCTAssertTrue(fan.waitForExistence(timeout: 10))
        fan.click()
        XCTAssertTrue(app.buttons["System Monitor"].waitForExistence(timeout: 5))
        app.buttons["System Monitor"].click()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.windows["main"].screenshot())
        screenshot.name = "Native menu after ordinary relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCPUPopupAppearanceAndDismissal() throws {
        try verifyMenu(kind: "cpu", prefix: "CPU")
    }

    @MainActor
    func testMemoryPopupAppearanceAndDismissal() throws {
        try verifyMenu(kind: "memory", prefix: "Memory")
    }

    @MainActor
    func testDrivePopupAppearanceAndDismissal() throws {
        try verifyMenu(kind: "drive", prefix: "Drive")
    }

    @MainActor
    func testIndependentReadingControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopMenuBarOrderUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-priority-list-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Menu Bar"].waitForExistence(timeout: 5))
        app.buttons["Menu Bar"].click()
        XCTAssertTrue(app.staticTexts["Readings"].waitForExistence(timeout: 5))
        let titles = ["Show fan speed", "Show temperature", "Show CPU usage", "Show GPU usage",
                      "Show memory usage", "Show drive usage", "Show battery"]
        let controls = titles.map { title in
            app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND elementType != %d", title, XCUIElement.ElementType.staticText.rawValue
            )).firstMatch
        }
        for control in controls { XCTAssertTrue(control.exists) }
        for pair in zip(controls, controls.dropFirst()) { XCTAssertLessThan(pair.0.frame.midY, pair.1.frame.midY) }
        let cpu = app.menuBars.statusItems.matching(NSPredicate(format: "label BEGINSWITH 'CPU' OR title BEGINSWITH 'CPU'")).firstMatch
        XCTAssertTrue(cpu.waitForExistence(timeout: 10))
        controls[2].click()
        XCTAssertTrue(cpu.waitForNonExistence(timeout: 5))
        for prefix in ["Chip temperature", "Memory", "Drive"] {
            XCTAssertTrue(app.menuBars.statusItems.matching(NSPredicate(format: "label BEGINSWITH %@ OR title BEGINSWITH %@", prefix, prefix)).firstMatch.waitForExistence(timeout: 5), prefix)
        }
        controls[2].click()
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemperatureOnlyMenuInLightAndDark() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopMenuBarOrderUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-temperature-monochrome-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 5))
        app.popUpButtons["Appearance"].click()
        app.menuItems["Dark"].click()
        let temperature = app.menuBars.statusItems.matching(NSPredicate(
            format: "label BEGINSWITH 'Chip temperature' OR title BEGINSWITH 'Chip temperature'"
        )).firstMatch
        XCTAssertTrue(temperature.waitForExistence(timeout: 10))
        for appearance in ["Dark", "Light"] {
            app.popUpButtons["Appearance"].click()
            app.menuItems[appearance].click()
            // Native menu extras can mark the application AX node disabled while
            // their status button remains clickable in the system menu bar.
            temperature.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(app.staticTexts["temperatureMenuTitle"].waitForExistence(timeout: 5), app.debugDescription)
            let title = app.staticTexts["temperatureMenuTitle"]
            XCTAssertTrue([title.label, title.value as? String ?? ""].contains("Temperature"))
            XCTAssertFalse(app.staticTexts["Power & electrical"].exists)
            capture("Temperature only · \(appearance)")
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            XCTAssertTrue(app.staticTexts["temperatureMenuTitle"].waitForNonExistence(timeout: 5))
        }
        app.buttons["Menu Bar"].click()
        XCTAssertTrue(app.staticTexts["Readings"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func verifyMenu(kind: String, prefix: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-usage-ui-%p.profraw"
        defer { app.terminate() }

        // Keep each click target out of macOS overflow on a crowded menu bar.
        app.launchArguments = ["-CachePopDemo", "-CachePopUsageUITest", "-CachePopUsageMenu=\(kind)",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings,'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(app.buttons["General"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["General"].click()
        XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 5), app.debugDescription)
        app.popUpButtons["Appearance"].click()
        app.menuItems["Light"].click()
        let item = app.menuBars.statusItems.matching(NSPredicate(format: "title BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.staticTexts["\(kind)MenuTitle"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["\(kind)MenuTitle"].isHittable)
        XCTAssertFalse(app.buttons["Scan for Junk"].exists)
        switch kind {
        case "cpu":
            XCTAssertTrue(app.staticTexts["Idle"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["View All Processes"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "usageProcess0").firstMatch.waitForExistence(timeout: 10))
        case "memory":
            XCTAssertTrue(app.staticTexts["Swap"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Compressed"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "usageProcess0").firstMatch.waitForExistence(timeout: 10))
        default:
            XCTAssertTrue(app.staticTexts["Capacity"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Drive activity"].exists)
            XCTAssertTrue(app.buttons["Open Drive in Finder"].exists)
            XCTAssertTrue(app.buttons["Disk Usage"].exists)
            XCTAssertTrue(app.buttons["Find Large Files"].exists)
        }
        let panel = app.descendants(matching: .popover).containing(.staticText, identifier: "\(kind)MenuTitle").firstMatch
        XCTAssertTrue(panel.exists, app.debugDescription)
        capture("\(prefix) · Light")

        // A click in CachePop's own window must dismiss without swallowing it.
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.8)).click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "\(prefix) should close on a click in the main window.")
        capture("\(prefix) · Light · menu bar reading")
        app.popUpButtons["Appearance"].click()
        app.menuItems["Dark"].click()
        XCTAssertEqual(app.popUpButtons["Appearance"].value as? String, "Dark")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        capture("\(prefix) · Dark")

        // Also cover a click delivered to another app. Opening Finder's menu does not change any files.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.menuBars.menuBarItems["Finder"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "\(prefix) should close on a click outside CachePop.")
        finder.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        if kind == "memory" {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(app.buttons["View All Processes"].waitForExistence(timeout: 5))
            app.buttons["View All Processes"].click()
            let processes = app.staticTexts["Busiest apps and processes"]
            XCTAssertTrue(processes.waitForExistence(timeout: 10))
            XCTAssertTrue(processes.isHittable, "The process action should scroll System Monitor to its process list.")
        }
        app.terminate()
    }

    @MainActor
    private func capture(_ name: String) {
        // Status popovers can belong to any connected display on macOS.
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let screenshot = XCTAttachment(screenshot: screen.screenshot())
            screenshot.name = "\(name) · display \(index + 1)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
