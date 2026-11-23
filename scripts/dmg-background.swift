import AppKit

// The installer artwork is drawn in points and exported at 1× and 2× so Finder stays sharp
// on Retina displays. The application and Applications folder are real, draggable Finder icons.
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: dmg-background.swift <output.tiff> <brand-glyph.png>\n", stderr)
    exit(64)
}
let output = URL(fileURLWithPath: arguments[1])
guard let glyph = NSImage(contentsOfFile: arguments[2]) else {
    fputs("Could not load the CachePop brand glyph.\n", stderr)
    exit(1)
}

let canvas = NSSize(width: 760, height: 480)
let ink = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
func text(_ value: String, _ rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = ink, alignment: NSTextAlignment = .left, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking
    ])
}

let brandGlyph = NSImage(size: glyph.size, flipped: false) { rect in
    glyph.draw(in: rect)
    ink.setFill()
    rect.fill(using: .sourceIn)
    return true
}

func drawBackground() {
    let bounds = NSRect(origin: .zero, size: canvas)
    NSColor.white.setFill()
    bounds.fill()

    brandGlyph.draw(in: NSRect(x: 49, y: 32, width: 15, height: 29), from: .zero,
                    operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    text("CachePop", NSRect(x: 77, y: 33, width: 190, height: 31), size: 22, weight: .semibold, tracking: -0.4)

    text("A little space. A fresh start.", NSRect(x: 40, y: 106, width: 680, height: 44),
         size: 32, weight: .semibold, alignment: .center, tracking: -0.8)

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 350, y: 271))
    arrow.line(to: NSPoint(x: 410, y: 271))
    arrow.move(to: NSPoint(x: 399, y: 260))
    arrow.line(to: NSPoint(x: 410, y: 271))
    arrow.line(to: NSPoint(x: 399, y: 282))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    ink.setStroke()
    arrow.stroke()
    text("Drag to install", NSRect(x: 308, y: 296, width: 144, height: 20), size: 11.5,
         weight: .medium, alignment: .center)
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 48, y: 414))
    divider.line(to: NSPoint(x: 712, y: 414))
    divider.lineWidth = 1
    ink.withAlphaComponent(0.1).setStroke()
    divider.stroke()
    text("More room for what matters.", NSRect(x: 48, y: 425, width: 300, height: 19),
         size: 11, color: ink.withAlphaComponent(0.6))
    text("Eject this disk after installing.", NSRect(x: 410, y: 425, width: 302, height: 19),
         size: 11, color: ink.withAlphaComponent(0.6), alignment: .right)
}

var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
                                  pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = canvas
    representations.append(bitmap)
}
guard let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: representations, using: .lzw, factor: 1),
      let preview = representations.last?.representation(using: .png, properties: [:]) else {
    fputs("Could not render the installer background.\n", stderr)
    exit(1)
}
try tiff.write(to: output, options: .atomic)
try preview.write(to: output.deletingPathExtension().appendingPathExtension("png"), options: .atomic)
