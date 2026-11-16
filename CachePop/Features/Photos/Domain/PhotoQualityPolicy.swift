import Foundation

nonisolated enum PhotoQualityPolicy {
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

}
