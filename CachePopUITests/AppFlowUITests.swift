import XCTest

/// Exercises the main product flows against disposable demo data, without confirming removal.
final class AppFlowUITests: XCTestCase {
    @MainActor
    func testCleanupEntrySelectionInLightAndDark() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
            app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
            app.typeKey(",", modifierFlags: .command)
            XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 5))
            app.popUpButtons["Appearance"].click()
            app.menuItems[appearance].click()
            app.typeKey("1", modifierFlags: .command)
            XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5))
            app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
            XCTAssertTrue(app.buttons["Clean…"].waitForExistence(timeout: 45))
            for id in ["xcode.derivedData", "xcode.deviceSupport.iOS DeviceSupport", "xcode.caches", "xcode.archives"] {
                XCTAssertFalse(app.buttons["cleanupViewAll.\(id)"].exists)
                XCTAssertFalse(app.buttons["cleanupExpand.\(id)"].exists)
            }
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 projects · Largest:' OR value BEGINSWITH '2 projects · Largest:'")).firstMatch.exists)
            let xcodeDisclosure = app.buttons["cleanupGroupDisclosure.xcode"]
            XCTAssertTrue(xcodeDisclosure.exists)
            let derivedSelection = app.buttons["Select Derived data"].value as? String
            xcodeDisclosure.click()
            XCTAssertTrue(app.buttons["Select Derived data"].waitForNonExistence(timeout: 5))
            XCTAssertEqual(xcodeDisclosure.value as? String, "Collapsed")
            capture("Collapsed Xcode section \(appearance)", app: app)
            xcodeDisclosure.click()
            XCTAssertTrue(app.buttons["Select Derived data"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["Select Derived data"].value as? String, derivedSelection)
            capture("Simplified Xcode cards \(appearance)", app: app)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupViewAll.simulators.'")).count, 0)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupExpand.simulators.'")).count, 0)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupViewAll.dev.'")).count, 0)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupExpand.dev.'")).count, 0)
            let cloneCards = app.buttons.matching(NSPredicate(format: "label == 'Select Clone of iPhone 16'"))
            XCTAssertEqual(cloneCards.count, 3)
            for _ in 0..<8 where !cloneCards.firstMatch.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -300) }
            capture("Individual simulator clone cards \(appearance)", app: app)
            // General rows use the disclosure arrow to keep individual choices accessible.
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupViewAll.general.'")).count, 0)
            let entryDisclosure = app.buttons["cleanupExpand.general.installers"]
            XCTAssertTrue(entryDisclosure.exists)
            let windowFrame = app.windows["main"].frame
            for _ in 0..<20 {
                let center = entryDisclosure.frame.midY
                if entryDisclosure.isHittable && center > windowFrame.minY + 100 && center < windowFrame.maxY - 110 { break }
                app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: center < windowFrame.minY + 100 ? 150 : -150)
            }
            XCTAssertTrue(entryDisclosure.isHittable)
            capture("Grouped cleanup sections \(appearance)", app: app)
            entryDisclosure.click()
            let sheet = app.sheets.firstMatch
            XCTAssertTrue(sheet.buttons["Deselect All"].waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.buttons["Select Figma-2026.dmg"].exists)
            XCTAssertTrue(sheet.buttons["Select OldTool.pkg"].exists)
            XCTAssertEqual(sheet.buttons["Select OldTool.pkg"].value as? String, "Not selected")
            sheet.buttons["Deselect All"].click()
            sheet.buttons["Select Figma-2026.dmg"].click()
            let summary = sheet.staticTexts["cleanupEntrySelectionSummary"]
            XCTAssertTrue((summary.value as? String ?? summary.label).hasPrefix("1 of 2 selected"))
            let search = sheet.textFields["cleanupEntrySearch"]
            search.click()
            search.typeText("OldTool.pkg")
            XCTAssertTrue(sheet.buttons["Select OldTool.pkg"].exists)
            XCTAssertFalse(sheet.buttons["Select Figma-2026.dmg"].exists)
            search.typeKey("a", modifierFlags: .command)
            search.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
            capture("Choose cleanup entries \(appearance)", app: app)
            sheet.buttons["Done"].click()
            XCTAssertTrue(entryDisclosure.waitForExistence(timeout: 5))
            entryDisclosure.click()
            XCTAssertTrue(sheet.buttons["Deselect All"].waitForExistence(timeout: 5))
            XCTAssertTrue((summary.value as? String ?? summary.label).hasPrefix("1 of 2 selected"))
            sheet.buttons["Done"].click()
            app.buttons["Clean…"].click()
            XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.sheets.firstMatch.staticTexts["Installers in Downloads"].exists)
            XCTAssertFalse(app.sheets.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Figma-2026.dmg' OR value CONTAINS 'Figma-2026.dmg'")).firstMatch.exists)
            XCTAssertFalse(app.sheets.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'OldTool.pkg' OR value CONTAINS 'OldTool.pkg'")).firstMatch.exists)
            capture("Chosen entry confirmation \(appearance)", app: app)
            app.sheets.firstMatch.buttons["Cancel"].click()
        }
    }

    @MainActor
    func testMainSectionsAndReviewFlows() throws {
        for appearance in ["Light", "Dark"] { try verifyMainSections(appearance: appearance) }
    }

    @MainActor
    private func verifyMainSections(appearance: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-audit-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()
        let window = app.windows["main"]
        XCTAssertLessThanOrEqual(window.frame.width, 960)
        XCTAssertLessThanOrEqual(window.frame.height, 690)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 5))
        app.popUpButtons["Appearance"].click()
        app.menuItems[appearance].click()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5))
        capture("Clean Up Start \(appearance)", app: app)
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        capture("History \(appearance)", app: app)
        app.buttons["Done"].click()
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(app.buttons["Clean…"].waitForExistence(timeout: 45))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cleanupViewAll.browsers.'")).count, 0)
        capture("Compact Clean Up", app: app)
        app.buttons["Clean…"].click()
        XCTAssertTrue(app.sheets.firstMatch.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("Clean Up Confirmation \(appearance)", app: app)
        app.sheets.firstMatch.buttons["Cancel"].click()

        app.typeKey("2", modifierFlags: .command)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Find Large Files"].waitForExistence(timeout: 5))
        capture("Large Files Start \(appearance)", app: app)
        app.buttons["Find Large Files"].click()
        XCTAssertTrue(app.buttons["Start Over"].waitForExistence(timeout: 30))
        capture("Compact Large Files", app: app)
        let duplicates = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Duplicates'")).firstMatch
        XCTAssertTrue(duplicates.waitForExistence(timeout: 5))
        duplicates.click()
        capture("Compact duplicate headers \(appearance)", app: app)

        app.typeKey("1", modifierFlags: .command)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Find Large Files"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Check Photos"].waitForExistence(timeout: 5))
        capture("Photos Start \(appearance)", app: app)
        app.buttons["Check Photos"].click()
        XCTAssertTrue(app.buttons["Start Over"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Retake'")).firstMatch.exists)
        capture("Compact Photos", app: app)

        app.typeKey("2", modifierFlags: .command)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Check Photos"].waitForExistence(timeout: 5))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 10))
        capture("Compact System Monitor", app: app)
        app.buttons["monitorDetails"].click()
        XCTAssertTrue(app.buttons["Reset Peaks"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()

        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Measure My Disk"].waitForExistence(timeout: 5))
        app.buttons["Measure My Disk"].click()
        let library = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Library'")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        capture("Compact Disk Usage", app: app)
        library.click()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
        app.buttons["Back"].click()

        app.typeKey("4", modifierFlags: .command)
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Measure My Disk"].waitForExistence(timeout: 5))
        app.typeKey("6", modifierFlags: .command)
        let scanApplications = app.buttons["Scan Applications"]
        XCTAssertTrue(scanApplications.waitForExistence(timeout: 5))
        XCTAssertFalse(scanApplications.waitForNonExistence(timeout: 1), "Opening Applications must wait for an explicit scan.")
        XCTAssertFalse(app.staticTexts["Demo Editor"].firstMatch.exists)
        capture("Applications Start Light", app: app)
        scanApplications.click()
        XCTAssertTrue(app.staticTexts["Demo Editor"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Uninstall…"].exists)
        capture("Compact Applications", app: app)
        app.buttons["Uninstall…"].click()
        XCTAssertTrue(app.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()

        app.typeKey("1", modifierFlags: .command)
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(scanApplications.waitForExistence(timeout: 5), "Returning to Applications should show its initial screen.")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Demo Editor"].firstMatch.waitForExistence(timeout: 15))

        app.typeKey("7", modifierFlags: .command)
        let scanLoginItems = app.buttons["Scan Login Items"]
        XCTAssertTrue(scanLoginItems.waitForExistence(timeout: 5))
        XCTAssertFalse(scanLoginItems.waitForNonExistence(timeout: 1), "Opening Login Items must wait for an explicit scan.")
        XCTAssertFalse(app.checkBoxes["Start Dropbox automatically"].exists)
        capture("Login Items Start Light", app: app)
        scanLoginItems.click()
        XCTAssertTrue(app.checkBoxes["Start Dropbox automatically"].waitForExistence(timeout: 10))
        capture("Compact Login Items", app: app)
        XCTAssertEqual(app.buttons.matching(identifier: "Login Items Settings").count, 1)
        app.typeKey("1", modifierFlags: .command)
        app.typeKey("7", modifierFlags: .command)
        XCTAssertTrue(scanLoginItems.waitForExistence(timeout: 5), "Returning to Login Items should show its initial screen.")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(app.checkBoxes["Start Dropbox automatically"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Menu Bar"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Menu Bar"].click()
        for label in ["Show CPU usage", "Show memory usage", "Show drive usage"] {
            let control = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND elementType != %d", label, XCUIElement.ElementType.staticText.rawValue
            )).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "The switch needs an accessible name: \(label)")
            XCTAssertNotNil(control.value)
        }
        for tab in ["Clean Up", "Never Clean", "Large Files", "Menu Bar", "General"] {
            app.buttons[tab].click()
            capture("Settings \(tab) \(appearance)", app: app)
        }
        app.popUpButtons["Appearance"].click()
        app.menuItems["Dark"].click()
        XCTAssertEqual(app.popUpButtons["Appearance"].value as? String, "Dark")
        capture("Compact Settings Dark", app: app)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Scan My Mac"].waitForExistence(timeout: 5), "Navigation should return to the initial screen.")
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(scanApplications.waitForExistence(timeout: 5))
        capture("Applications Start Dark", app: app)
        app.typeKey("7", modifierFlags: .command)
        XCTAssertTrue(scanLoginItems.waitForExistence(timeout: 5))
        capture("Login Items Start Dark", app: app)
    }

    @MainActor
    func testDownloadsThresholdMenuInLightAndDark() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopAuditUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-threshold-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["Appearance"].waitForExistence(timeout: 10))
        for appearance in ["Dark", "Light"] {
            app.buttons["General"].click()
            app.popUpButtons["Appearance"].click()
            app.menuItems[appearance].click()
            app.buttons["Clean Up"].click()
            let threshold = app.descendants(matching: .any).matching(identifier: "redownloadThresholdMenu").firstMatch
            XCTAssertTrue(threshold.waitForExistence(timeout: 5))
            threshold.click()
            app.menuItems["Over 250 MB"].click()
            XCTAssertEqual(threshold.value as? String, "Over 250 MB")
            threshold.click()
            app.menuItems["Over 100 MB"].click()
            XCTAssertEqual(threshold.value as? String, "Over 100 MB")
            capture("Blue threshold menu \(appearance)", app: app)
        }
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
