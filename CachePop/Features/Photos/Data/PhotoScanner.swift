import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Photos
import Synchronization
import Vision

/// Finds photos, measures each one, and groups retakes. Read-only: removing is the view model's.
nonisolated enum PhotoScanner {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"
    ]
    /// Smaller images are icons, stickers and thumbnails, not photos.
    static let minimumSide = 600
    /// Photos measured at once.
    static let width = min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 4)

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
        var identity: FileReviewIdentity? = nil
        /// Display fallback only. Files can be copied together long after capture.
        var fileCreationDate: Date? = nil
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

        // Process chronological neighbours together. Only a small window of Vision
        // feature prints is needed, rather than a vector for every photo in the library.
        candidates.sort {
            let lhs = $0.date ?? .distantPast, rhs = $1.date ?? .distantPast
            if lhs != rhs { return lhs < rhs }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.location.photoID < $1.location.photoID
        }
        let total = candidates.count
        progress(0, total)
        var builder = PhotoGroupBuilder<FeaturePrint>()
        await withTaskGroup(of: Measured.self) { group in
            var scheduled = 0
            var consumed = 0
            var pending: [Int: Measured] = [:]
            func fill() {
                while !Task.isCancelled, scheduled < candidates.count, scheduled - consumed < width {
                    let index = scheduled
                    let candidate = candidates[index]
                    scheduled += 1
                    group.addTask { Measured(index: index, result: measure(candidate, library: library)) }
                }
            }
            fill()
            var done = 0
            while let measured = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                pending[measured.index] = measured
                done += 1
                if done % 10 == 0 || done == total { progress(done, total) }
                while let next = pending.removeValue(forKey: consumed) {
                    if let result = next.result {
                        autoreleasepool {
                            builder.append(photo(result.0, metrics: result.1), feature: result.2) { first, second in
                                PhotoAnalyzer.distance(first.observation, second.observation)
                            }
                        }
                    }
                    consumed += 1
                }
                // A slow image cannot let the out-of-order buffer grow past worker width.
                fill()
            }
        }
        guard !Task.isCancelled else { return .empty }
        return builder.finish()
    }

    private struct Measured: Sendable {
        let index: Int
        let result: (Candidate, PhotoMetrics, FeaturePrint?)?
    }

    /// Favourites come first. For comparable focus, preserve the more detailed original.
    static func isBetter(_ first: AnalyzedPhoto, _ second: AnalyzedPhoto) -> Bool {
        if first.isFavorite != second.isFavorite { return first.isFavorite }
        // Favourites hide quality labels in review, but their measurements still inform the keeper.
        let firstIssue = first.isFavorite ? PhotoAnalyzer.issue(for: first.metrics) : first.issue
        let secondIssue = second.isFavorite ? PhotoAnalyzer.issue(for: second.metrics) : second.issue
        if (firstIssue == nil) != (secondIssue == nil) { return firstIssue == nil }
        let firstBand = first.metrics.sharpnessBand
        let secondBand = second.metrics.sharpnessBand
        if firstBand != secondBand { return firstBand > secondBand }
        let firstArea = first.pixelWidth * first.pixelHeight
        let secondArea = second.pixelWidth * second.pixelHeight
        if firstArea != secondArea { return firstArea > secondArea }
        if first.metrics.sharpness != second.metrics.sharpness { return first.metrics.sharpness > second.metrics.sharpness }
        return first.id < second.id
    }

    static func photo(_ candidate: Candidate, metrics: PhotoMetrics) -> AnalyzedPhoto {
        AnalyzedPhoto(
            id: candidate.location.photoID, location: candidate.location, name: candidate.name,
            date: candidate.date ?? candidate.fileCreationDate,
            pixelWidth: candidate.pixelWidth, pixelHeight: candidate.pixelHeight, bytes: candidate.bytes,
            isFavorite: candidate.isFavorite, metrics: metrics,
            issue: candidate.isFavorite ? nil : PhotoAnalyzer.issue(for: metrics), identity: candidate.identity
        )
    }

    static func measure(_ candidate: Candidate, library: LibraryAssets?) -> (Candidate, PhotoMetrics, FeaturePrint?)? {
        autoreleasepool {
            guard let image = image(for: candidate, library: library, side: PhotoAnalyzer.side),
                  let metrics = PhotoAnalyzer.metrics(of: image) else { return nil }
            let feature = candidate.date == nil ? nil : PhotoAnalyzer.featurePrint(of: image).map(FeaturePrint.init)
            return (candidate, metrics, feature)
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
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .creationDateKey]
        var candidates: [Candidate] = []
        var seen = Set<String>()

        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            var done = false
            while !done {
                if Task.isCancelled { return [] }
                autoreleasepool {
                    guard var url = enumerator.nextObject() as? URL else { done = true; return }
                    let values = try? url.resourceValues(forKeys: keys)
                    if values?.isDirectory == true {
                        if LargeFilesScanner.skippedFolderNames.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                        return
                    }
                    guard values?.isRegularFile == true,
                          imageExtensions.contains(url.pathExtension.lowercased()),
                          !seen.contains(url.standardizedFileURL.path),
                          let identity = FileReviewIdentity.read(url),
                          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          isCameraPhoto(properties) else { return }
                    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                    guard max(width, height) >= minimumSide else { return }
                    seen.insert(url.standardizedFileURL.path)
                    url.removeAllCachedResourceValues()
                    candidates.append(Candidate(
                        location: .file(url), name: url.lastPathComponent,
                        date: captureDate(properties),
                        pixelWidth: width, pixelHeight: height,
                        bytes: values?.fileSize.map(Int64.init), isFavorite: false, identity: identity,
                        fileCreationDate: values?.creationDate
                    ))
                }
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
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String,
           let date = offsetCaptureDateFormatter.date(from: text + offset) { return date }
        return captureDateFormatter.date(from: text)
    }

    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static let offsetCaptureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
        return formatter
    }()

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

        result.enumerateObjects { asset, index, stop in
            guard !Task.isCancelled else { stop.pointee = true; return }
            autoreleasepool {
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
    static let memoryBudget = 8 * 1_024 * 1_024
    private static let revision = Mutex<Int>(0)
    nonisolated final class Box: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 64
        cache.totalCostLimit = memoryBudget
        return cache
    }()

    @concurrent
    static func load(_ photo: AnalyzedPhoto, side: Int) async -> Box? {
        guard !Task.isCancelled else { return nil }
        let generation = revision.withLock { $0 }
        let key = "\(generation)#\(photo.id)#\(side)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image: CGImage? = switch photo.location {
        case .file(let url): PhotoScanner.fileImage(url, side: side)
        case .library(let identifier): PhotoScanner.libraryImage(identifier: identifier, side: side)
        }
        guard let image, !Task.isCancelled else { return nil }
        let box = Box(image)
        return revision.withLock {
            guard $0 == generation else { return nil }
            cache.setObject(box, forKey: key, cost: image.bytesPerRow * image.height)
            return box
        }
    }

    static func clear() {
        revision.withLock { $0 &+= 1; cache.removeAllObjects() }
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
