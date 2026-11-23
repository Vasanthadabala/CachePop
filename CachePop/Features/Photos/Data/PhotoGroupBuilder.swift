import Foundation

/// Groups retakes in capture order, keeping only the most recent feature prints.
nonisolated struct PhotoGroupBuilder<Feature> {
    private var groups: [[AnalyzedPhoto]] = []
    private var neighbours: [(group: Int, date: Date, feature: Feature)] = []
    private var analyzedCount = 0

    mutating func append(_ photo: AnalyzedPhoto, feature: Feature?, distance: (Feature, Feature) -> Float?) {
        analyzedCount += 1
        guard let date = photo.date, let feature else {
            groups.append([photo])
            return
        }
        neighbours.removeAll { date.timeIntervalSince($0.date) > PhotoAnalyzer.similarWindow }

        var matches: [Int: (count: Int, largestDistance: Float)] = [:]
        for previous in neighbours {
            guard !Task.isCancelled else { return }
            if let value = distance(previous.feature, feature), value < PhotoAnalyzer.similarDistance {
                let prior = matches[previous.group, default: (0, 0)]
                matches[previous.group] = (prior.count + 1, max(prior.largestDistance, value))
            }
        }

        // Require a direct match to every member, including the eventual keeper.
        // A group with an expired or evicted feature can no longer accept a shot.
        let best = matches.filter { $0.value.count == groups[$0.key].count }.min {
            if $0.value.largestDistance == $1.value.largestDistance { return $0.key < $1.key }
            return $0.value.largestDistance < $1.value.largestDistance
        }
        let group = best?.key ?? groups.count
        if group == groups.count { groups.append([]) }
        groups[group].append(photo)
        neighbours.append((group, date, feature))
        if neighbours.count > PhotoAnalyzer.neighbours { neighbours.removeFirst() }
    }

    mutating func finish() -> PhotoScanResult {
        neighbours.removeAll()
        guard !Task.isCancelled else { return .empty }
        var result = PhotoScanResult()
        result.analyzedCount = analyzedCount
        for members in groups {
            if members.count > 1 {
                let group = members.sorted(by: PhotoScanner.isBetter)
                result.similar.append(SimilarGroup(id: group[0].id, photos: group))
            } else if let photo = members.first, let issue = photo.issue {
                result.issues[issue, default: []].append(photo)
            }
        }
        result.similar.sort { ($0.photos[0].date ?? .distantPast) > ($1.photos[0].date ?? .distantPast) }
        for issue in PhotoIssue.allCases {
            result.issues[issue]?.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        return result
    }
}
