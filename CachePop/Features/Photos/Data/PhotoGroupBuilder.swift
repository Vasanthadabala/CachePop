import Foundation

/// Retake matching in chronological order. A feature is compared with at most the
/// previous 40 valid features from the last ten minutes, then old features are released.
/// Photo metadata stays available for the review, without retaining every Vision vector.
nonisolated struct PhotoGroupBuilder<Feature> {
    private var photos: [AnalyzedPhoto] = []
    private var parent: [Int] = []
    private var neighbours: [(index: Int, date: Date, feature: Feature)] = []

    mutating func append(_ photo: AnalyzedPhoto, feature: Feature?, distance: (Feature, Feature) -> Float?) {
        let index = photos.count
        photos.append(photo)
        parent.append(index)
        guard let date = photo.date, let feature else { return }
        neighbours.removeAll { date.timeIntervalSince($0.date) > PhotoAnalyzer.similarWindow }
        // Union by index keeps groups deterministic, including transitive retakes.
        var matches: [Int] = []
        for previous in neighbours {
            guard !Task.isCancelled else { return }
            if let value = distance(previous.feature, feature), value < PhotoAnalyzer.similarDistance {
                matches.append(previous.index)
            }
        }
        for previous in matches {
            let currentRoot = root(index)
            let previousRoot = root(previous)
            parent[currentRoot] = previousRoot
        }
        neighbours.append((index, date, feature))
        if neighbours.count > PhotoAnalyzer.neighbours { neighbours.removeFirst() }
    }

    private mutating func root(_ value: Int) -> Int {
        var index = value
        while parent[index] != index {
            parent[index] = parent[parent[index]]
            index = parent[index]
        }
        return index
    }

    mutating func finish() -> PhotoScanResult {
        neighbours.removeAll()
        guard !Task.isCancelled else { return .empty }
        var groups: [Int: [Int]] = [:]
        for index in photos.indices { groups[root(index), default: []].append(index) }
        var result = PhotoScanResult()
        result.analyzedCount = photos.count
        for indices in groups.values {
            if indices.count > 1 {
                let group = indices.map { photos[$0] }.sorted(by: PhotoScanner.isBetter)
                result.similar.append(SimilarGroup(id: group[0].id, photos: group))
            } else if let index = indices.first, let issue = photos[index].issue {
                result.issues[issue, default: []].append(photos[index])
            }
        }
        result.similar.sort { ($0.photos[0].date ?? .distantPast) > ($1.photos[0].date ?? .distantPast) }
        for issue in PhotoIssue.allCases {
            result.issues[issue]?.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        return result
    }
}
