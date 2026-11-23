import CoreGraphics
import Foundation
import Vision

nonisolated enum PhotoAnalyzer {
    /// Photos are measured at this size: enough to see blur, quick to read.
    static let side = 512
    static let grid = 4

    static let blurrySharpness = PhotoQualityPolicy.blurrySharpness
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

        let fine = tileSharpness(pixels, width: width, height: height)
        // At half scale adjacent pixels reinforce real contours, while independent grain averages out.
        let coarseWidth = width / 2
        let coarseHeight = height / 2
        var coarse = [UInt8](repeating: 0, count: coarseWidth * coarseHeight)
        for y in 0..<coarseHeight {
            for x in 0..<coarseWidth {
                let i = 2 * (y * width + x)
                let top = Int(pixels[i]) + Int(pixels[i + 1])
                let bottom = Int(pixels[i + width]) + Int(pixels[i + width + 1])
                coarse[y * coarseWidth + x] = UInt8((top + bottom + 2) / 4)
            }
        }
        let broad = tileSharpness(coarse, width: coarseWidth, height: coarseHeight)

        // Trim 5% at each end so isolated black or white pixels cannot establish tonal detail.
        let toneSamples = coarse.isEmpty ? pixels : coarse
        var histogram = [Int](repeating: 0, count: 256)
        for value in toneSamples { histogram[Int(value)] += 1 }
        let trim = toneSamples.count / 20
        func firstTone(afterTrimming bins: some Sequence<Int>) -> Int {
            var cumulative = 0
            for bin in bins {
                cumulative += histogram[bin]
                if cumulative > trim { return bin }
            }
            return 0
        }
        let lowTone = firstTone(afterTrimming: histogram.indices)
        let highTone = firstTone(afterTrimming: histogram.indices.reversed())

        return PhotoMetrics(
            sharpness: max(fine, broad * 0.5),
            brightness: luminance / count / 255,
            shadows: Double(dark) / count,
            highlights: Double(bright) / count,
            lowTone: lowTone, highTone: highTone
        )
    }

    private static func tileSharpness(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        let noiseFloor = laplacianNoiseFloor(pixels, width: width, height: height)
        // Suppress sensor noise before bounding extreme edges such as hot pixels.
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
                    let response = center - around
                    let magnitude = min(96, max(0, abs(response) - noiseFloor))
                    let laplacian = response < 0 ? -magnitude : magnitude
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
        return sharpness
    }

    /// Estimate the noise in a Laplacian response from diagonal differences in sampled
    /// 2×2 blocks. Smooth gradients cancel, and the median resists isolated subject edges.
    private static func laplacianNoiseFloor(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 1, height > 1 else { return 0 }
        var histogram = [Int](repeating: 0, count: 17)
        var count = 0
        for y in stride(from: 0, to: height - 1, by: 3) {
            let row = y * width
            for x in stride(from: 0, to: width - 1, by: 3) {
                let i = row + x
                let diagonal = Int(pixels[i]) + Int(pixels[i + width + 1])
                let opposite = Int(pixels[i + 1]) + Int(pixels[i + width])
                histogram[min(abs(diagonal - opposite), histogram.count - 1)] += 1
                count += 1
            }
        }
        var cumulative = 0
        for (value, frequency) in histogram.enumerated() {
            cumulative += frequency
            // For independent Gaussian noise, six times the median absolute diagonal
            // difference is about 1.8 standard deviations of the Laplacian response.
            if cumulative > count / 2 { return Double(value * 6) }
        }
        return 0
    }

    // MARK: Similar photos

    /// Vision's description of what's in the photo, for telling near-identical shots apart.
    static func featurePrint(of image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
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
    /// Maximum number of prior feature prints kept for direct comparisons.
    static let neighbours = 40

}
