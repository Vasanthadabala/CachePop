import AppKit

/// A compact Apple-style case with charge digits and a charging bolt inside.
/// Charge digits reverse contrast over the fill; the lightning bolt stays black.
enum BatteryMenuBarIcon {
    static func image(percent: Int?, showsBolt: Bool) -> NSImage {
        let scale = MenuBarItemLayout.batteryScale
        let contentWidth = MenuBarItemLayout.contentWidth(for: MenuBarItemLayout.width * 0.6)
        let level = percent.map { min(max($0, 0), 100) }
        let text = level.map { "\($0)" } ?? "—"
        // Grays sampled from the supplied native macOS battery reference.
        let foreground = referenceGray(243)
        let remainder = referenceGray(133)
        let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black]))
        let image = NSImage(size: NSSize(width: contentWidth * scale, height: MenuBarItemLayout.height), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: 0, yBy: MenuBarItemLayout.height * (1 - scale) / 2)
            transform.scale(by: scale)
            transform.concat()
            let bodyWidth = min(36, contentWidth - 4.5)
            let body = NSRect(x: (contentWidth - bodyWidth - 3.2) / 2, y: 4.5, width: bodyWidth, height: 13)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
            foreground.setStroke()
            outline.lineWidth = 1.1
            outline.stroke()
            referenceGray(111).setFill()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 1.5, y: 9, width: 1.7, height: 4), xRadius: 0.7, yRadius: 0.7).fill()

            let inside = body.insetBy(dx: 1.6, dy: 1.6)
            let track = NSBezierPath(roundedRect: inside, xRadius: 1.4, yRadius: 1.4)
            remainder.setFill()
            track.fill()
            let fill = NSRect(x: inside.minX, y: inside.minY, width: inside.width * CGFloat(level ?? 0) / 100, height: inside.height)
            NSGraphicsContext.saveGraphicsState()
            track.addClip()
            foreground.setFill()
            NSBezierPath(rect: fill).fill()
            NSGraphicsContext.restoreGraphicsState()

            let label = text as NSString
            let preferredFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            let naturalWidth = label.size(withAttributes: [.font: preferredFont]).width
            let availableWidth = inside.width - 1 - (showsBolt ? 7 : 0)
            let fontSize = min(10, 10 * availableWidth / max(naturalWidth, 1))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: foreground
            ]
            let size = label.size(withAttributes: attributes)
            let groupWidth = size.width + (showsBolt ? 7 : 0)
            let start = body.midX - groupWidth / 2
            let origin = NSPoint(x: start, y: body.midY - size.height / 2)
            let boltRect = NSRect(x: start + size.width + 1.5, y: body.midY - 4.5, width: 5.5, height: 9)
            label.draw(at: origin, withAttributes: attributes)
            // Knock the digits out of the light fill; keep them light over the gray remainder.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fill).addClip()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            label.draw(at: origin, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
            if showsBolt { bolt?.draw(in: boltRect, from: .zero, operation: .sourceOver, fraction: 1) }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func referenceGray(_ level: CGFloat) -> NSColor {
        let value = level / 255
        return NSColor(calibratedRed: value, green: value, blue: value, alpha: 1)
    }
}
