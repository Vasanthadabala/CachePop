import XCTest

final class WindowLayoutUITests: XCTestCase {
    @MainActor
    func testIntroPagesExpandAndNavigationSurvivesResizingAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-CachePopUsageUITest",
                               "-CachePopUsageMenu=sensors", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["main"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        for (index, expanded) in [false, true, false, true].enumerated() {
            if index > 0 {
                let previous = window.frame.width
                let zoom = window.buttons[XCUIIdentifierFullScreenWindow]
                XCTAssertTrue(zoom.exists)
                XCUIElement.perform(withKeyModifiers: .option) { zoom.click() }
                let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(window.frame.width - previous) > 30 }, object: nil)
                capture(window, name: "Native zoom operation \(index)")
                XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 10), .completed)
            }
            for key in ["1", "2", "3", "5", "6", "7"] {
                app.typeKey(key, modifierFlags: .command)
                assertIntroFillsDetail(app, window: window)
            }
            if expanded {
                let header = app.descendants(matching: .any).matching(identifier: "featureIntroHeader").firstMatch
                XCTAssertGreaterThan(header.frame.width, 1_040)
            }
        }
        capture(window, name: "Expanded intro with permanent navigation")

        app.typeKey("q", modifierFlags: .command)
        app.activate()
        app.typeKey("p", modifierFlags: [.command, .control])
        XCTAssertTrue(app.buttons["Open CachePop"].waitForExistence(timeout: 5))
        app.buttons["Open CachePop"].click()
        app.typeKey("5", modifierFlags: .command)
        assertIntroFillsDetail(app, window: window)
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(app.staticTexts["sensorsMenuTitle"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        assertIntroFillsDetail(app, window: window)
        capture(window, name: "Navigation restored after menu bar mode")
    }

    @MainActor
    func testCleanupDoneAppearsInTheVisibleCompletionSummary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["main"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        app.typeKey("1", modifierFlags: .command)
        app.buttons["Scan My Mac"].click()
        XCTAssertTrue(app.buttons["Clean…"].waitForExistence(timeout: 45))
        app.buttons["Clean…"].click()
        let confirm = app.sheets.firstMatch.buttons["Clean"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click() // Only the disposable demo home is cleaned.
        let done = app.buttons["cleanUpDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 45))
        XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThan(done.frame.minX, window.frame.midX)
        XCTAssertEqual(done.frame.maxX, window.frame.maxX - 40, accuracy: 4)
        XCTAssertLessThan(done.frame.minY, window.frame.minY + 350)
        XCTAssertLessThan(done.frame.maxY, app.staticTexts["What was cleaned"].frame.minY)
        capture(window, name: "Done action in cleanup summary")
        done.click()
        XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertIntroFillsDetail(_ app: XCUIApplication, window: XCUIElement) {
        let sidebar = app.descendants(matching: .any).matching(identifier: "appSidebar").firstMatch
        let header = app.descendants(matching: .any).matching(identifier: "featureIntroHeader").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebar.frame.width, 236, accuracy: 2)
        XCTAssertEqual(header.frame.width, window.frame.width - 236 - 40, accuracy: 5)
        XCTAssertGreaterThanOrEqual(app.staticTexts["pageTitle"].frame.minX, sidebar.frame.maxX + 16)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings'")).firstMatch.isHittable)
    }

    @MainActor
    private func capture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
