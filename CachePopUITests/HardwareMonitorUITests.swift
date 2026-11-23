import XCTest

final class HardwareMonitorUITests: XCTestCase {
    @MainActor
    func testCPUAndMemoryProcessColumnsStayAligned() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-process-columns-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.typeKey("4", modifierFlags: .command)
        let pages = app.descendants(matching: .any).matching(identifier: "monitorPages").firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 10))
        for title in ["CPU", "Memory"] {
            pages.descendants(matching: .radioButton).matching(identifier: title).firstMatch.click()
            let values = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'processValue-'"))
            XCTAssertTrue(values.firstMatch.waitForExistence(timeout: 15))
            app.scrollViews["monitorPageContent"].scroll(byDeltaX: 0, deltaY: -2_000)
            let visibleValues = values.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 0 }
            XCTAssertGreaterThan(visibleValues.count, 1)
            if let edge = visibleValues.first?.frame.maxX {
                for value in visibleValues { XCTAssertEqual(value.frame.maxX, edge, accuracy: 1) }
            }
            let pids = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'processPID-'"))
                .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 0 }
            XCTAssertGreaterThan(pids.count, 1)
            if let edge = pids.first?.frame.maxX {
                for pid in pids { XCTAssertEqual(pid.frame.maxX, edge, accuracy: 1) }
            }
            XCTAssertTrue(app.staticTexts["Quit"].exists)
            let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
            attachment.name = "\(title) aligned process columns"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

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
            for title in ["CPU", "GPU", "Memory", "Drive", "Battery", "Sensors"] {
                let radios = pages.descendants(matching: .radioButton).matching(identifier: title)
                let control = radios.firstMatch.exists ? radios.firstMatch : pages.buttons[title].firstMatch
                XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
                control.click()
                switch title {
                case "GPU": XCTAssertTrue(app.descendants(matching: .any)["gpuMonitorCard"].firstMatch.waitForExistence(timeout: 5))
                case "Drive": XCTAssertTrue(app.descendants(matching: .any)["mountedDrives"].firstMatch.waitForExistence(timeout: 5))
                case "Sensors": XCTAssertTrue(app.descendants(matching: .any)["sensorReadings"].firstMatch.waitForExistence(timeout: 5))
                case "Battery":
                    XCTAssertTrue(app.staticTexts["Battery power"].waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts["24 hours ago"].exists)
                    XCTAssertTrue(app.staticTexts["Last 24 hours"].exists)
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
