import CoreGraphics
import Foundation
import Vision

/// What CachePop measures in a photo, from a copy at most `PhotoAnalyzer.side` pixels across.
nonisolated struct PhotoMetrics: Sendable, Equatable, Hashable {
    /// Edge strength in the sharpest part of the photo: the variance of the Laplacian in the
    /// best tile of a 4×4 grid. A sharp subject on a soft background still counts as sharp.
    var sharpness: Double
    /// Mean luminance, 0…1.
    var brightness: Double
    /// Share of pixels that are nearly black.
    var shadows: Double
    /// Share of pixels that are nearly white.
    var highlights: Double
}

/// Why a photo is worth a look.
nonisolated enum PhotoIssue: String, CaseIterable, Identifiable, Sendable {
    case blurry, dark, overexposed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blurry:      "Blurry"
        case .dark:        "Too dark"
        case .overexposed: "Overexposed"
        }
    }
}

nonisolated enum PhotoAnalyzer {
    /// Photos are measured at this size: enough to see blur, quick to read.
    static let side = 512
    static let grid = 4

    // Thresholds. A photo gets at most one issue; dark and overexposed are checked first,
    // since both also flatten edges and would otherwise read as blurry.
    // Calibrated on sharp photos (780–6,750) against blurred, darkened and brightened copies.
    static let blurrySharpness = 80.0
    static let darkBrightness = 0.12
    static let darkShadows = 0.65
    static let overexposedBrightness = 0.88
    static let overexposedHighlights = 0.40

    static func issue(for metrics: PhotoMetrics) -> PhotoIssue? {
        if metrics.brightness < darkBrightness || metrics.shadows > darkShadows { return .dark }
        if metrics.brightness > overexposedBrightness || metrics.highlights > overexposedHighlights { return .overexposed }
        if metrics.sharpness < blurrySharpness { return .blurry }
        return nil
    }

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

    /// Groups of indices into `dates` whose photos look alike and were taken close together,
    /// each in date order. `distance` compares two photos; nil means they can't be compared.
    static func similarGroups(dates: [Date?], distance: (Int, Int) -> Float?) -> [[Int]] {
        let order = dates.indices.filter { dates[$0] != nil }.sorted { dates[$0]! < dates[$1]! }
        var parent = Array(dates.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        for (position, first) in order.enumerated() {
            let start = dates[first]!
            for second in order.dropFirst(position + 1).prefix(neighbours) {
                guard dates[second]!.timeIntervalSince(start) <= similarWindow else { break }
                if let value = distance(first, second), value < similarDistance {
                    parent[root(second)] = root(first)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in order { groups[root(index), default: []].append(index) }
        return groups.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
    }
}
