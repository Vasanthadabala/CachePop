import Foundation

nonisolated enum PhotoQualityPolicy {
    // Thresholds. A photo gets at most one issue; dark and overexposed are checked first,
    // since both also flatten edges and would otherwise read as blurry.
    static let blurrySharpness = 80.0
    static let darkBrightness = 0.12
    static let darkShadows = 0.65
    static let overexposedBrightness = 0.88
    static let overexposedHighlights = 0.40

    // Allow a dark or bright background when the opposite tail still contains subject detail.
    static let darkestUpperTone = 64
    static let brightestLowerTone = 191
    static let minimumFocusToneRange = 32

    static func issue(for metrics: PhotoMetrics) -> PhotoIssue? {
        if metrics.highTone <= darkestUpperTone,
           metrics.brightness < darkBrightness || metrics.shadows > darkShadows {
            return .dark
        }
        if metrics.lowTone >= brightestLowerTone,
           metrics.brightness > overexposedBrightness || metrics.highlights > overexposedHighlights {
            return .overexposed
        }
        if metrics.highTone - metrics.lowTone >= minimumFocusToneRange, metrics.sharpness < blurrySharpness { return .blurry }
        return nil
    }

}
