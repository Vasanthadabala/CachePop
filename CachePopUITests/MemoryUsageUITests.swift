import AppKit
import Darwin
import XCTest

/// Repeatable fixture workload; samples the app, not the XCTest runner.
final class MemoryUsageUITests: XCTestCase {
    @MainActor
    func testMemoryAfterReviewAndMenuBarOnly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-CachePopMemoryUITest",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-memory-ui-%p.profraw"
        app.launchEnvironment["CACHEPOP_MEMORY_REPORT"] = "/tmp/CachePop-memory-benchmark.json"
        app.launch()
        defer { app.terminate() }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5))
        app.buttons["Scan My Mac"].click()
        XCTAssertTrue(app.buttons["Clean…"].waitForExistence(timeout: 45))
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan Applications"].waitForExistence(timeout: 5))
        app.buttons["Scan Applications"].click()
        XCTAssertTrue(app.staticTexts["Demo Editor"].firstMatch.waitForExistence(timeout: 15))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Check Photos"].waitForExistence(timeout: 5))
        app.buttons["Check Photos"].click()
        XCTAssertTrue(app.buttons["Start Over"].waitForExistence(timeout: 45))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<10 { scroll.swipeUp() }
        Thread.sleep(forTimeInterval: 2)
        app.typeKey("q", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 5)
        let fan = app.menuBars.statusItems.matching(NSPredicate(format: "label CONTAINS 'Fan speed' OR title CONTAINS 'Fan speed'")).firstMatch
        XCTAssertTrue(fan.waitForExistence(timeout: 10), "Fan monitoring must remain available.")
        fan.click()
        XCTAssertTrue(app.buttons["System Monitor"].waitForExistence(timeout: 5))
        app.buttons["System Monitor"].click()
        XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 5))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Clean…"].waitForExistence(timeout: 5), "Review state must survive unloading the window UI.")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Start Over"].waitForExistence(timeout: 5), "Photo results must survive too.")
        Thread.sleep(forTimeInterval: 2)
        app.typeKey("q", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 5)
    }
}
