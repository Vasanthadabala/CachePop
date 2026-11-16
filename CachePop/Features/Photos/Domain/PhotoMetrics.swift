import Foundation

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
