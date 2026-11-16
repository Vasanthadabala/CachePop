import CoreGraphics
import Foundation
import Vision

nonisolated enum PhotoAnalyzer {
    /// Photos are measured at this size: enough to see blur, quick to read.
    static let side = 512
    static let grid = 4

    static let blurrySharpness = PhotoQualityPolicy.blurrySharpness
    static let darkBrightness = PhotoQualityPolicy.darkBrightness
    static let darkShadows = PhotoQualityPolicy.darkShadows
    static let overexposedBrightness = PhotoQualityPolicy.overexposedBrightness
    static let overexposedHighlights = PhotoQualityPolicy.overexposedHighlights
    static func issue(for metrics: PhotoMetrics) -> PhotoIssue? { PhotoQualityPolicy.issue(for: metrics) }

    /// Reads `image` into 8-bit grey at most `side` across and measures it.
    static func metrics(of image: CGImage) -> PhotoMetrics? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Double(side) / Double(longest))
        let width = max(Int((Double(image.width) * scale).rounded()), grid * 3)
        let height = max(Int((Double(image.height) * scale).rounded()), grid * 3)

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return metrics(gray: pixels, width: width, height: height)
    }

    /// The measurements themselves, on 8-bit grey pixels in rows.
    static func metrics(gray pixels: [UInt8], width: Int, height: Int) -> PhotoMetrics {
        var luminance = 0.0
        var dark = 0
        var bright = 0
        for value in pixels {
            luminance += Double(value)
            if value < 16 { dark += 1 }
            if value > 245 { bright += 1 }
        }
        let count = Double(max(pixels.count, 1))

        // Laplacian per interior pixel, summed per tile.
        var sums = [Double](repeating: 0, count: grid * grid)
        var squares = [Double](repeating: 0, count: grid * grid)
        var counts = [Double](repeating: 0, count: grid * grid)
        if width > 2, height > 2 {
            for y in 1..<(height - 1) {
                let row = y * width
                let tileRow = min(y * grid / height, grid - 1) * grid
                for x in 1..<(width - 1) {
                    let center = Double(pixels[row + x]) * 4
                    let around = Double(pixels[row + x - 1]) + Double(pixels[row + x + 1])
                        + Double(pixels[row - width + x]) + Double(pixels[row + width + x])
                    let laplacian = center - around
                    let tile = tileRow + min(x * grid / width, grid - 1)
                    sums[tile] += laplacian
                    squares[tile] += laplacian * laplacian
                    counts[tile] += 1
                }
            }
        }
        var sharpness = 0.0
        for tile in 0..<(grid * grid) where counts[tile] > 0 {
            let mean = sums[tile] / counts[tile]
            sharpness = max(sharpness, squares[tile] / counts[tile] - mean * mean)
        }

        return PhotoMetrics(
            sharpness: sharpness,
            brightness: luminance / count / 255,
            shadows: Double(dark) / count,
            highlights: Double(bright) / count
        )
    }

    // MARK: Similar photos

    /// Vision's description of what's in the photo, for telling near-identical shots apart.
    static func featurePrint(of image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }

    static func distance(_ first: VNFeaturePrintObservation, _ second: VNFeaturePrintObservation) -> Float? {
        var distance: Float = 0
        guard (try? first.computeDistance(&distance, to: second)) != nil else { return nil }
        return distance
    }

    /// Feature prints closer than this are the same shot taken again. The same photo re-exposed
    /// measures about 0.1 and slightly reframed 0.3–0.5; different photos of one place 0.56 and up.
    static let similarDistance: Float = 0.40
    /// Only photos taken this close together are compared: retakes and bursts.
    static let similarWindow: TimeInterval = 10 * 60
    /// At most this many later photos are compared with each one.
    static let neighbours = 40

}
