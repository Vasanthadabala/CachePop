import AppKit
import SwiftUI
import Testing
@testable import CachePop

@Suite("Fixed menu bar capsules")
@MainActor
struct MenuBarLayoutTests {
    @Test func compactReadingsStayTwentyPercentNarrowerForSmallAndLargeValues() {
        let compact = MenuBarItemLayout.compactWidth
        let full = NSSize(width: MenuBarItemLayout.contentWidth, height: MenuBarItemLayout.height)
        #expect(compact == 56)
        for text in ["—", "0%", "9%", "100%", "999.99%", "9.9 GB", "999.9 GB"] {
            for kind in [UsageMenuKind.cpu, .gpu, .memory, .drive] {
                let width = StatusMenuKind.usage(kind).width
                let image = UsageMenuBarLabel.image(title: kind.title, value: text, width: width)
                #expect(image.size == NSSize(width: width - 8, height: full.height))
            }
        }
        for value in ["—", "9°C", "52°C", "105°C"] {
            let image = MenuBarItemLayout.image(width: compact) { TemperatureStatusReading(value: value) }
            #expect(image.size == NSSize(width: 48, height: full.height))
        }
        for value in ["↑ 0 B/s", "↑ 999.9 KB/s", "↑ 999.9 MB/s", "↑ 999.9 GB/s"] {
            #expect(HardwareMenuBarLabel.networkImage(upload: value, download: "↓ 999.9 MB/s").size == NSSize(width: compact - 8, height: full.height))
        }
        for percent in [nil, 0, 9, 78, 100] {
            for charging in [false, true] {
                let size = HardwareMenuBarLabel.batteryImage(percent: percent, isCharging: charging).size
                #expect(abs(size.width - 29.988) < 0.001 && size.height == full.height)
            }
        }
        #expect(HardwareMenuBarLabel.sensorsImage().size == NSSize(width: 48, height: full.height))
        for kind in StatusMenuKind.all {
            let compactKinds: [StatusMenuKind] = [.temperature, .usage(.cpu), .usage(.gpu), .usage(.memory), .usage(.drive), .usage(.sensors), .usage(.network)]
            let expected = kind == .cachePop ? CGFloat(35) : kind == .usage(.battery) ? CGFloat(38.8962) : compactKinds.contains(kind) ? compact : CGFloat(70)
            #expect(abs(kind.width - expected) < 0.001)
        }
    }

    @Test func fanTextShrinksWithoutMovingItsRotorOrChangingItsSlot() {
        let view = FanStatusContent(frame: NSRect(x: 0, y: 0, width: MenuBarItemLayout.width, height: 22))
        var rotorFrame: NSRect?
        for value in ["—", "900", "1,400 RPM", "12,000 RPM"] {
            view.reading.stringValue = value
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            let font = view.reading.font!
            let width = (value as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= view.reading.frame.width + 0.1)
            #expect(view.frame.width == MenuBarItemLayout.width)
            if let rotorFrame { #expect(view.rotor.frame == rotorFrame) }
            rotorFrame = view.rotor.frame
        }
    }

    @Test func nativeBatteryHasPercentageAndAChargingBolt() throws {
        #expect(NSImage(systemSymbolName: "battery.100percent.bolt", accessibilityDescription: nil) != nil)
        let idle = HardwareMenuBarLabel.batteryImage(percent: 78, isCharging: false)
        let charging = HardwareMenuBarLabel.batteryImage(percent: 78, isCharging: true)
        let pausedOnAdapter = HardwareMenuBarLabel.batteryImage(percent: 78, isCharging: false, isPluggedIn: true)
        #expect(pausedOnAdapter.tiffRepresentation == charging.tiffRepresentation, "The adapter should show the bolt even when charging is paused.")
        #expect(idle.size == charging.size)
        #expect(idle.tiffRepresentation != charging.tiffRepresentation)
        let data = try #require(idle.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        // The case and its internal percentage occupy both halves of the image.
        for area in [0..<(bitmap.pixelsWide / 2), (bitmap.pixelsWide / 2)..<bitmap.pixelsWide] {
            let visible = area.reduce(0) { count, x in
                count + (0..<bitmap.pixelsHigh).filter { (bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.1 }.count
            }
            #expect(visible > 30)
        }
        let chargedData = try #require(charging.tiffRepresentation)
        let chargedBitmap = try #require(NSBitmapImageRep(data: chargedData))
        var changes = 0
        let scale = CGFloat(bitmap.pixelsWide) / idle.size.width
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let a = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(chargedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if abs(a.alphaComponent - b.alphaComponent) > 0.03 {
                    changes += 1
                    #expect(CGFloat(x) / scale >= 0.8 && CGFloat(x) / scale <= 27)
                    #expect(CGFloat(y) / scale >= 5 && CGFloat(y) / scale <= 17)
                }
            }
        }
        #expect(changes > 10, "Charging changes must stay inside the battery case.")
        for image in [charging, HardwareMenuBarLabel.batteryImage(percent: 100, isCharging: true)] {
            let renderer = ImageRenderer(content: Image(nsImage: image).frame(width: image.size.width, height: image.size.height))
            renderer.scale = 3
            let pixels = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let pixelScale = CGFloat(pixels.pixelsWide) / image.size.width
            var blackBolt = 0
            for x in Int(19.8 * pixelScale)..<Int(25.9 * pixelScale) {
                for y in Int(7 * pixelScale)..<Int(15 * pixelScale) {
                    let color = try #require(pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if color.alphaComponent > 0.9 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.1 {
                        blackBolt += 1
                    }
                }
            }
            #expect(CGFloat(blackBolt) / (pixelScale * pixelScale) > 1, "The bolt must be opaque black, including over the unfilled part.")
        }
    }

    @Test func renderSmallAndLargeReadingProof() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CachePop-fixed-menu-bar.png")
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 12) {
            proofRow(temperature: "52°C", percent: "9%", upload: "↑ 5 KB/s", download: "↓ 16 KB/s", battery: 77, charging: true)
            proofRow(temperature: "105°C", percent: "100%", upload: "↑ 999.9 MB/s", download: "↓ 999.9 GB/s", battery: 100, charging: true)
        }.foregroundStyle(.white).padding(14).background(Color.black))
        renderer.scale = 3
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)
        print("Menu bar layout proof: \(file.path)")
    }

    private func proofRow(temperature: String, percent: String, upload: String, download: String,
                          battery: Int, charging: Bool) -> some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarLabel.glyph).frame(width: MenuBarItemLayout.brandWidth, height: 24)
                .background(Color(white: 0.2), in: Capsule())
            capsule(MenuBarItemLayout.image(width: MenuBarItemLayout.compactWidth) { TemperatureStatusReading(value: temperature) }, width: MenuBarItemLayout.compactWidth)
            capsule(UsageMenuBarLabel.image(title: "CPU", value: percent, width: MenuBarItemLayout.compactWidth), width: MenuBarItemLayout.compactWidth)
            capsule(UsageMenuBarLabel.image(title: "GPU", value: percent, width: MenuBarItemLayout.compactWidth), width: MenuBarItemLayout.compactWidth)
            capsule(UsageMenuBarLabel.image(title: "Memory", value: percent, width: MenuBarItemLayout.compactWidth), width: MenuBarItemLayout.compactWidth)
            capsule(UsageMenuBarLabel.image(title: "Drive", value: percent, width: MenuBarItemLayout.compactWidth), width: MenuBarItemLayout.compactWidth)
            capsule(HardwareMenuBarLabel.batteryImage(percent: battery, isCharging: charging), width: MenuBarItemLayout.batteryWidth)
            capsule(HardwareMenuBarLabel.sensorsImage(), width: MenuBarItemLayout.compactWidth)
            capsule(HardwareMenuBarLabel.networkImage(upload: upload, download: download), width: MenuBarItemLayout.compactWidth)
        }
    }

    private func capsule(_ image: NSImage, width: CGFloat = MenuBarItemLayout.width) -> some View {
        Image(nsImage: image).frame(width: width, height: 24)
            .background(Color(white: 0.2), in: Capsule())
    }
}
