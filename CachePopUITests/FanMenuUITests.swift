import AppKit
import XCTest

final class FanMenuUITests: XCTestCase {
    @MainActor
    func testFanRotationControlsAndMonitorDetails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopFanUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-fan-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        app.windows["main"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).click()

        let fan = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(fan.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'rpm'"), object: fan)], timeout: 10), .completed)

        // Capture the actual status button, including its layer animation, rather than a
        // synthesized SwiftUI preview. Several phases avoid sampling a full-turn alias.
        let first = fan.screenshot()
        let firstRotor = try rotorPixels(first, frame: fan.frame)
        var changed = false
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.17)
            let next = fan.screenshot()
            if firstRotor != (try rotorPixels(next, frame: fan.frame)) { changed = true }
            let attachment = XCTAttachment(screenshot: next)
            attachment.name = "Fan rotation frame"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(changed, "The spinning fan must render different visible frames.")
        }
        XCTAssertEqual(fan.value as? String, "Spinning")
        fan.click()

        let enable = app.buttons["enableFanControl"]
        XCTAssertTrue(enable.waitForExistence(timeout: 10), app.debugDescription)
        let fanPopup = XCTAttachment(screenshot: app.screenshot())
        fanPopup.name = "Fan popup colors"
        fanPopup.lifetime = .keepAlways
        add(fanPopup)
        enable.click() // DemoFanController only; never registers the real privileged helper.
        let custom = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Custom'")).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5), app.debugDescription)
        custom.click()
        XCTAssertTrue(app.sliders["fanTarget0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["fanTarget1"].exists)
        app.buttons["Full Speed"].click()
        XCTAssertTrue(app.staticTexts["5800 rpm"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["6200 rpm"].exists)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Automatic'")).firstMatch.click()
        XCTAssertFalse(app.sliders["fanTarget0"].exists)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Auto Boost'")).firstMatch.click()
        XCTAssertTrue(app.buttons["fanBoostRules"].exists)
        app.buttons["fanBoostRules"].click()
        XCTAssertTrue(app.buttons["Add Rule"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Automatic'")).firstMatch.click()
        app.buttons["System Monitor"].click()

        let details = app.buttons["monitorDetails"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.click()
        XCTAssertTrue(app.buttons["Reset Peaks"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Status Checks'")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["Temperature sensors"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "System Monitor status checks"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].click()
        let record = app.buttons["monitorRecording"]
        record.click()
        XCTAssertEqual(record.label, "Stop Recording")
        record.click()
        XCTAssertEqual(record.label, "Record")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.menuBars.statusItems.firstMatch.waitForExistence(timeout: 5))
        app.menuBars.statusItems.firstMatch.click()
        XCTAssertTrue(app.buttons["System Monitor"].waitForExistence(timeout: 5))
        app.buttons["System Monitor"].click()
        XCTAssertTrue(app.buttons["monitorDetails"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPopupRotorsStayCenteredWhileSpinningAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-CachePopDemo", "-CachePopFanUITest", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LLVM_PROFILE_FILE"] = NSTemporaryDirectory() + "CachePop-fan-popup-ui-%p.profraw"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 15))
        let fan = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(fan.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'rpm'"), object: fan)], timeout: 10), .completed)
        for opening in 0..<2 {
            fan.click()
            let rows = (0..<2).map { index in
                app.descendants(matching: .any).matching(identifier: "fanPopupRow\(index)").firstMatch
            }
            for row in rows { XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription) }
            var phases = [Set<Data>(), Set<Data>()]
            // Covers several full rotations and live RPM updates, including a new host on reopen.
            for frame in 0..<10 {
                for (index, row) in rows.enumerated() {
                    let screenshot = row.screenshot()
                    if frame < 3 {
                        let attachment = XCTAttachment(screenshot: screenshot)
                        attachment.name = "Popup \(opening) fan \(index + 1) frame \(frame)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    let pixels = try popupRotorPixels(screenshot, frame: row.frame)
                    phases[index].insert(pixels)
                }
                Thread.sleep(forTimeInterval: 0.17)
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                for phase in phases { XCTAssertGreaterThan(phase.count, 2, "Each popup fan must keep turning.") }
            }
            fan.click()
            XCTAssertFalse(rows[0].exists)
        }
    }

    private func popupRotorPixels(_ screenshot: XCUIScreenshot, frame: CGRect) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
        let image = try XCTUnwrap(bitmap.cgImage)
        let scale = CGFloat(bitmap.pixelsWide) / frame.width
        let rect = CGRect(x: 0, y: (CGFloat(bitmap.pixelsHigh) - 22 * scale) / 2,
                          width: 22 * scale, height: 22 * scale).integral
        let cropped = try XCTUnwrap(image.cropping(to: rect))
        let rotor = NSBitmapImageRep(cgImage: cropped)
        let background = try XCTUnwrap(rotor.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)).redComponent
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<rotor.pixelsHigh {
            for x in 0..<rotor.pixelsWide {
                if let color = rotor.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   abs(color.redComponent - background) > 0.2 {
                    xs.append(x); ys.append(y)
                }
            }
        }
        XCTAssertGreaterThan(xs.count, 20, "The blades must remain visible.")
        if let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() {
            XCTAssertLessThanOrEqual(abs(CGFloat(left + right + 1) / 2 - CGFloat(rotor.pixelsWide) / 2), 1.5 * scale,
                                     "The rotor must turn around its horizontal center.")
            XCTAssertLessThanOrEqual(abs(CGFloat(top + bottom + 1) / 2 - CGFloat(rotor.pixelsHigh) / 2), 1.5 * scale,
                                     "The rotor must turn around its vertical center.")
        }
        return try XCTUnwrap(rotor.representation(using: .png, properties: [:]))
    }

    private func rotorPixels(_ screenshot: XCUIScreenshot, frame: CGRect) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
        let image = try XCTUnwrap(bitmap.cgImage)
        let scale = CGFloat(bitmap.pixelsHigh) / max(frame.height, 1)
        let rect = CGRect(x: 6 * scale, y: (CGFloat(bitmap.pixelsHigh) - 16 * scale) / 2,
                          width: 16 * scale, height: 16 * scale).integral
        let cropped = try XCTUnwrap(image.cropping(to: rect))
        let rotor = NSBitmapImageRep(cgImage: cropped)
        let background = try XCTUnwrap(rotor.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)).redComponent
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<rotor.pixelsHigh {
            for x in 0..<rotor.pixelsWide {
                if let color = rotor.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   abs(color.redComponent - background) > 0.2 {
                    xs.append(x); ys.append(y)
                }
            }
        }
        XCTAssertGreaterThan(xs.count, 10, "Fan blades must remain visible throughout the turn.")
        if let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() {
            XCTAssertLessThanOrEqual(abs(CGFloat(left + right + 1) / 2 - CGFloat(rotor.pixelsWide) / 2), 2 * scale)
            XCTAssertLessThanOrEqual(abs(CGFloat(top + bottom + 1) / 2 - CGFloat(rotor.pixelsHigh) / 2), 2 * scale)
        }
        return try XCTUnwrap(rotor.representation(using: .png, properties: [:]))
    }
}
