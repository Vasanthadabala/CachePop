import Foundation

/// Where a photo lives: a file in one of your folders, or an asset in the Photos library.
nonisolated enum PhotoLocation: Sendable, Hashable {
    case file(URL)
    case library(String)
}


nonisolated struct AnalyzedPhoto: Identifiable, Sendable, Hashable {
    let id: String
    let location: PhotoLocation
    let name: String
    let date: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    /// File size for photos in folders. The Photos library doesn't say.
    let bytes: Int64?
    let isFavorite: Bool
    let metrics: PhotoMetrics
    /// Never set for favourites.
    let issue: PhotoIssue?
    var identity: FileReviewIdentity? = nil

    var isInLibrary: Bool {
        if case .library = location { return true }
        return false
    }

    var fileURL: URL? {
        if case .file(let url) = location { return url }
        return nil
    }
}


/// Shots that look alike and were taken close together. Best first: the one to keep.
nonisolated struct SimilarGroup: Identifiable, Sendable, Hashable {
    let id: String
    var photos: [AnalyzedPhoto]
}


nonisolated struct PhotoScanResult: Sendable {
    var similar: [SimilarGroup] = []
    /// Photos with an issue that aren't in a similar group.
    var issues: [PhotoIssue: [AnalyzedPhoto]] = [:]
    var analyzedCount = 0

    static let empty = PhotoScanResult()

    func photos(with issue: PhotoIssue) -> [AnalyzedPhoto] { issues[issue] ?? [] }

    var allPhotos: [AnalyzedPhoto] { similar.flatMap(\.photos) + issues.values.flatMap { $0 } }

    /// Extra shots in similar groups plus every photo with an issue.
    var reviewCount: Int {
        similar.reduce(0) { $0 + $1.photos.count - 1 } + issues.values.reduce(0) { $0 + $1.count }
    }

    /// Drops removed photos and groups left with a single shot.
    mutating func remove(_ ids: Set<String>) {
        similar = similar.compactMap { group in
            let photos = group.photos.filter { !ids.contains($0.id) }
            return photos.count > 1 ? SimilarGroup(id: group.id, photos: photos) : nil
        }
        for issue in PhotoIssue.allCases {
            issues[issue] = issues[issue]?.filter { !ids.contains($0.id) }
        }
    }

    /// A successful Put Back changes file timestamps; keep those reviewed files usable.
    mutating func refreshRestoredIdentities(_ identities: [String: FileReviewIdentity]) {
        guard !identities.isEmpty else { return }
        for group in similar.indices {
            for index in similar[group].photos.indices {
                if let path = similar[group].photos[index].fileURL?.path, let identity = identities[path] {
                    similar[group].photos[index].identity = identity
                }
            }
        }
        for issue in PhotoIssue.allCases {
            for index in (issues[issue] ?? []).indices {
                if let path = issues[issue]?[index].fileURL?.path, let identity = identities[path] {
                    issues[issue]?[index].identity = identity
                }
            }
        }
    }
}
