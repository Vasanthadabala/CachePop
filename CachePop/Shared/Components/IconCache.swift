import AppKit
import UniformTypeIdentifiers

/// File and app icons, drawn once as small bitmaps and kept.
///
/// macOS hands back icons with every size up to 1024 px; drawing one of those into a 30 pt row
/// on each redraw is what made lists of apps stutter. A bitmap at twice the shown size looks the
/// same on Retina screens and costs next to nothing to draw. Safe to call off the main thread.
nonisolated enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 800
        return cache
    }()

    /// The icon Finder shows for `path`, sized for `points`. A missing file gets `fallback`'s icon.
    static func icon(forFile path: String, points: CGFloat, fallback: UTType = .item) -> NSImage {
        let key = "\(path)|\(Int(points.rounded(.up)))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let source = FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path)
            : NSWorkspace.shared.icon(for: fallback)
        let image = thumbnail(of: source, points: points)
        cache.setObject(image, forKey: key)
        return image
    }

    /// `image` drawn once into a bitmap at twice `points`, for Retina screens.
    static func thumbnail(of image: NSImage, points: CGFloat) -> NSImage {
        let pixels = max(1, Int((points * 2).rounded(.up)))
        var proposed = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let bitmap = context.makeImage() else { return image }
        return NSImage(cgImage: bitmap, size: NSSize(width: points, height: points))
    }
}
