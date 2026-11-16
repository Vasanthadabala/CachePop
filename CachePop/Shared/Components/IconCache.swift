import AppKit
import Synchronization
import UniformTypeIdentifiers

/// File and app icons, drawn once as small bitmaps and kept.
///
/// macOS hands back icons with every size up to 1024 px; drawing one of those into a 30 pt row
/// on each redraw is what made lists of apps stutter. A bitmap at twice the shown size looks the
/// same on Retina screens and costs next to nothing to draw. Safe to call off the main thread.
nonisolated enum IconCache {
    private static let revision = Mutex<Int>(0)
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 4 * 1_024 * 1_024
        return cache
    }()

    @concurrent
    static func load(forFile path: String, points: CGFloat, fallback: UTType = .item) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let image = autoreleasepool { icon(forFile: path, points: points, fallback: fallback) }
        return Task.isCancelled ? nil : image
    }

    /// The icon Finder shows for `path`, sized for `points`. A missing file gets `fallback`'s icon.
    static func icon(forFile path: String, points: CGFloat, fallback: UTType = .item) -> NSImage {
        let generation = revision.withLock { $0 }
        let key = "\(generation)|\(path)|\(Int(points.rounded(.up)))|\(fallback.identifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let source = FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path)
            : NSWorkspace.shared.icon(for: fallback)
        let image = thumbnail(of: source, points: points)
        let cost = image.representations.reduce(0) { $0 + max($1.pixelsWide, 0) * max($1.pixelsHigh, 0) * 4 }
        revision.withLock {
            if $0 == generation { cache.setObject(image, forKey: key, cost: cost) }
        }
        return image
    }

    static func clear() { revision.withLock { $0 &+= 1; cache.removeAllObjects() } }

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
