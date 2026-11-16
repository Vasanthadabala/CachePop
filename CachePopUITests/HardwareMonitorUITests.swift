import XCTest

final class HardwareMonitorUITests: XCTestCase {
    @MainActor
    func testSixMonitoringModulesInLightAndDark() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-hardware-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        for appearance in ["Light", "Dark"] {
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 5))
            app.popUpButtons["Appearance"].click()
            app.menuItems[appearance].click()
            app.typeKey("4", modifierFlags: .command)
            XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 10))
            let pages = app.descendants(matching: .any).matching(identifier: "monitorPages").firstMatch
            XCTAssertTrue(pages.waitForExistence(timeout: 5))
            for title in ["CPU", "GPU", "Drive", "Memory", "Sensors", "Battery"] {
                let radios = pages.descendants(matching: .radioButton).matching(identifier: title)
                let control = radios.firstMatch.exists ? radios.firstMatch : pages.buttons[title].firstMatch
                XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
                control.click()
                switch title {
                case "GPU": XCTAssertTrue(app.descendants(matching: .any)["gpuMonitorCard"].firstMatch.waitForExistence(timeout: 5))
                case "Drive": XCTAssertTrue(app.descendants(matching: .any)["mountedDrives"].firstMatch.waitForExistence(timeout: 5))
                case "Sensors": XCTAssertTrue(app.descendants(matching: .any)["sensorReadings"].firstMatch.waitForExistence(timeout: 5))
                case "Battery": XCTAssertTrue(app.staticTexts["Battery power"].waitForExistence(timeout: 5))
                default: break
                }
                let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
                attachment.name = "\(title) Monitor \(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
