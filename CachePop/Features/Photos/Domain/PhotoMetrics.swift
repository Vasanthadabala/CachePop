import Foundation

/// What CachePop measures in a photo, from a copy at most `PhotoAnalyzer.side` pixels across.
nonisolated struct PhotoMetrics: Sendable, Equatable, Hashable {
    /// Strongest tile response across two preview scales, after suppressing estimated noise.
    var sharpness: Double
    /// Mean luminance, 0…1.
    var brightness: Double
    /// Share of pixels that are nearly black.
    var shadows: Double
    /// Share of pixels that are nearly white.
    var highlights: Double
    /// Endpoints of the central 90% of block-averaged grayscale samples, on the 0…255 scale.
    var lowTone: Int
    var highTone: Int

    /// Quarter stops of edge energy keep small measurement differences from dominating keeper selection.
    /// Fixed bands give the sort a consistent order even in groups of three or more shots.
    var sharpnessBand: Int { Int((4 * log2(max(1, sharpness))).rounded()) }
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
