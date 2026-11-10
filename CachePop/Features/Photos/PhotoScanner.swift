import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Photos
import Vision

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
    var notes: [String] = []

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
}

/// Finds photos, measures each one, and groups retakes. Read-only: removing is the view model's.
nonisolated enum PhotoScanner {
    nonisolated enum Scope: String, CaseIterable, Identifiable, Sendable {
        case both, library, folders

        var id: String { rawValue }

        var title: String {
            switch self {
            case .both:    "Photos library and folders"
            case .library: "Photos library"
            case .folders: "Pictures, Desktop, Downloads and Documents"
            }
        }

        var includesLibrary: Bool { self != .folders }
        var includesFolders: Bool { self != .library }
    }

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"
    ]
    /// Smaller images are icons, stickers and thumbnails, not photos.
    static let minimumSide = 600
    /// Photos measured at once.
    static let width = max(ProcessInfo.processInfo.activeProcessorCount / 2, 2)

    static func photoFolders(home: URL) -> [URL] {
        ["Pictures", "Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    nonisolated struct Candidate: Sendable {
        let location: PhotoLocation
        let name: String
        let date: Date?
        let pixelWidth: Int
        let pixelHeight: Int
        let bytes: Int64?
        let isFavorite: Bool
        /// Position in the library fetch, for loading the image.
        var libraryIndex: Int?
    }

    /// A Photos fetch, read from the analysis tasks. Fetch results are immutable.
    nonisolated final class LibraryAssets: @unchecked Sendable {
        let result: PHFetchResult<PHAsset>
        init(_ result: PHFetchResult<PHAsset>) { self.result = result }
    }

    nonisolated final class FeaturePrint: @unchecked Sendable {
        let observation: VNFeaturePrintObservation
        init(_ observation: VNFeaturePrintObservation) { self.observation = observation }
    }

    // MARK: Scan

    /// `progress` gets (measured, total). Off the main actor, and stops when cancelled.
    @concurrent
    static func scan(
        folders: [URL],
        includeLibrary: Bool,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> PhotoScanResult {
        var candidates = fileCandidates(in: folders)
        var library: LibraryAssets?
        if includeLibrary {
            let fetched = libraryCandidates()
            library = fetched.assets
            candidates += fetched.candidates
        }
        guard !Task.isCancelled else { return .empty }

        let total = candidates.count
        progress(0, total)
        var measured: [(candidate: Candidate, metrics: PhotoMetrics, print: FeaturePrint?)] = []
        measured.reserveCapacity(total)

        await withTaskGroup(of: (Candidate, PhotoMetrics, FeaturePrint?)?.self) { group in
            var next = 0
            func add() {
                guard next < candidates.count else { return }
                let candidate = candidates[next]
                next += 1
                group.addTask { measure(candidate, library: library) }
            }
            for _ in 0..<width { add() }
            var done = 0
            for await result in group {
                done += 1
                if let result { measured.append(result) }
                if done % 10 == 0 || done == total { progress(done, total) }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                add()
            }
        }
        guard !Task.isCancelled else { return .empty }

        return assemble(measured.map { entry in
            (photo: photo(entry.candidate, metrics: entry.metrics), print: entry.print)
        })
    }

    /// Groups retakes and sorts out the rest by issue.
    static func assemble(_ measured: [(photo: AnalyzedPhoto, print: FeaturePrint?)]) -> PhotoScanResult {
        let dates = measured.map { $0.print == nil ? nil : $0.photo.date }
        let groups = PhotoAnalyzer.similarGroups(dates: dates) { first, second in
            guard let a = measured[first].print, let b = measured[second].print else { return nil }
            return PhotoAnalyzer.distance(a.observation, b.observation)
        }

        var result = PhotoScanResult()
        result.analyzedCount = measured.count
        var grouped = Set<Int>()
        for indices in groups {
            grouped.formUnion(indices)
            let photos = indices.map { measured[$0].photo }.sorted(by: isBetter)
            result.similar.append(SimilarGroup(id: photos[0].id, photos: photos))
        }
        result.similar.sort { ($0.photos[0].date ?? .distantPast) > ($1.photos[0].date ?? .distantPast) }

        for (index, entry) in measured.enumerated() where !grouped.contains(index) {
            if let issue = entry.photo.issue { result.issues[issue, default: []].append(entry.photo) }
        }
        for issue in PhotoIssue.allCases {
            result.issues[issue]?.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        return result
    }

    /// Which of two shots to keep: a favourite, then one without an issue, then the sharper,
    /// then the larger.
    static func isBetter(_ first: AnalyzedPhoto, _ second: AnalyzedPhoto) -> Bool {
        if first.isFavorite != second.isFavorite { return first.isFavorite }
        if (first.issue == nil) != (second.issue == nil) { return first.issue == nil }
        if first.metrics.sharpness != second.metrics.sharpness { return first.metrics.sharpness > second.metrics.sharpness }
        return first.pixelWidth * first.pixelHeight > second.pixelWidth * second.pixelHeight
    }

    static func photo(_ candidate: Candidate, metrics: PhotoMetrics) -> AnalyzedPhoto {
        let id: String
        switch candidate.location {
        case .file(let url): id = "file:" + url.path
        case .library(let identifier): id = "library:" + identifier
        }
        return AnalyzedPhoto(
            id: id, location: candidate.location, name: candidate.name, date: candidate.date,
            pixelWidth: candidate.pixelWidth, pixelHeight: candidate.pixelHeight, bytes: candidate.bytes,
            isFavorite: candidate.isFavorite, metrics: metrics,
            issue: candidate.isFavorite ? nil : PhotoAnalyzer.issue(for: metrics)
        )
    }

    static func measure(_ candidate: Candidate, library: LibraryAssets?) -> (Candidate, PhotoMetrics, FeaturePrint?)? {
        autoreleasepool {
            guard let image = image(for: candidate, library: library, side: PhotoAnalyzer.side),
                  let metrics = PhotoAnalyzer.metrics(of: image) else { return nil }
            return (candidate, metrics, PhotoAnalyzer.featurePrint(of: image).map(FeaturePrint.init))
        }
    }

    static func image(for candidate: Candidate, library: LibraryAssets?, side: Int) -> CGImage? {
        switch candidate.location {
        case .file(let url):
            return fileImage(url, side: side)
        case .library:
            guard let library, let index = candidate.libraryIndex, index < library.result.count else { return nil }
            return libraryImage(library.result.object(at: index), side: side)
        }
    }

    // MARK: Folders

    /// Camera photos in `folders`: image files with a camera's EXIF data, at least
    /// `minimumSide` across. Screenshots, icons and downloaded graphics have none.
    static func fileCandidates(in folders: [URL]) -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey]
        var candidates: [Candidate] = []
        var seen = Set<String>()

        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return [] }
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    if LargeFilesScanner.skippedFolderNames.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                    continue
                }
                guard values?.isRegularFile == true,
                      imageExtensions.contains(url.pathExtension.lowercased()),
                      seen.insert(url.standardizedFileURL.path).inserted else { continue }

                let candidate: Candidate? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          isCameraPhoto(properties) else { return nil }
                    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                    guard max(width, height) >= minimumSide else { return nil }
                    return Candidate(
                        location: .file(url), name: url.lastPathComponent,
                        date: captureDate(properties) ?? values?.creationDate,
                        pixelWidth: width, pixelHeight: height,
                        bytes: values?.fileSize.map(Int64.init), isFavorite: false
                    )
                }
                if let candidate { candidates.append(candidate) }
            }
        }
        return candidates
    }

    /// True when a camera wrote the file: a make or model, or exposure settings.
    static func isCameraPhoto(_ properties: [CFString: Any]) -> Bool {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        return tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil
            || exif[kCGImagePropertyExifExposureTime] != nil || exif[kCGImagePropertyExifFNumber] != nil
    }

    /// When the shot was taken, from EXIF ("2026:07:14 13:02:05").
    static func captureDate(_ properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        guard let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    static func fileImage(_ url: URL, side: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    // MARK: Photos library

    /// Every photo in the library except screenshots, newest first.
    static func libraryCandidates() -> (assets: LibraryAssets, candidates: [Candidate]) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(result.count)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        result.enumerateObjects { asset, index, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot),
                  max(asset.pixelWidth, asset.pixelHeight) >= minimumSide else { return }
            candidates.append(Candidate(
                location: .library(asset.localIdentifier),
                name: asset.creationDate.map { formatter.string(from: $0) } ?? "Photo",
                date: asset.creationDate,
                pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                bytes: nil, isFavorite: asset.isFavorite, libraryIndex: index
            ))
        }
        return (LibraryAssets(result), candidates)
    }

    /// A local copy of the photo at most `side` across. Never downloads from iCloud.
    static func libraryImage(_ asset: PHAsset, side: Int) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let slot = ImageSlot()
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
        ) { result, _ in
            slot.image = result?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return slot.image
    }

    /// Filled by Photos' synchronous callback before `requestImage` returns.
    nonisolated private final class ImageSlot: @unchecked Sendable {
        var image: CGImage?
    }

    static func libraryImage(identifier: String, side: Int) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return nil }
        return libraryImage(asset, side: side)
    }
}

// MARK: - Thumbnails

/// Small copies for the review grid, loaded as rows appear and kept for a while.
nonisolated enum PhotoThumbnails {
    nonisolated final class Box: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 600
        return cache
    }()

    @concurrent
    static func load(_ photo: AnalyzedPhoto, side: Int) async -> Box? {
        let key = "\(photo.id)#\(side)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image: CGImage? = switch photo.location {
        case .file(let url): PhotoScanner.fileImage(url, side: side)
        case .library(let identifier): PhotoScanner.libraryImage(identifier: identifier, side: side)
        }
        guard let image else { return nil }
        let box = Box(image)
        cache.setObject(box, forKey: key)
        return box
    }
}

// MARK: - Photos access and removal

nonisolated enum PhotosLibraryAccess {
    /// Asks the first time; afterwards returns what the user chose.
    static func request() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized
    }

    /// Moves the photos to Recently Deleted. Photos asks the user to confirm first; declining
    /// throws.
    static func delete(_ identifiers: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil))
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!
}
