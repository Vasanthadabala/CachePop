import AppKit

/// A text-free white charge icon, without status-color tinting.
/// Charge level and charging remain visible, with the percentage available to accessibility.
enum BatteryMenuBarIcon {
    static func image(percent: Int?, isCharging: Bool) -> NSImage {
        let level = percent.map { CGFloat(min(max($0, 0), 100)) / 100 }
        let image = NSImage(size: NSSize(width: 26, height: 18), flipped: false) { _ in
            NSColor.white.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 21, height: 12), xRadius: 2.5, yRadius: 2.5)
            body.lineWidth = 1.2
            body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 23.2, y: 7, width: 1.6, height: 4), xRadius: 0.7, yRadius: 0.7).fill()
            if let level {
                if level > 0 {
                    NSBezierPath(roundedRect: NSRect(x: 3.2, y: 5.2, width: 16.6 * level, height: 7.6), xRadius: 0.8, yRadius: 0.8).fill()
                }
            } else {
                NSBezierPath(rect: NSRect(x: 8, y: 8.3, width: 7, height: 1.4)).fill()
            }
            if isCharging {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 12.6, y: 14))
                bolt.line(to: NSPoint(x: 8.3, y: 8.3))
                bolt.line(to: NSPoint(x: 11, y: 8.3))
                bolt.line(to: NSPoint(x: 10.2, y: 4))
                bolt.line(to: NSPoint(x: 15, y: 10))
                bolt.line(to: NSPoint(x: 12, y: 10))
                bolt.close()
                // A transparent outline separates the bolt from any charge fill.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                bolt.lineWidth = 2
                bolt.stroke()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.white.setFill()
                bolt.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
