import AppKit
import SwiftUI

@Observable
@MainActor
final class PhotosViewModel {
    enum Phase { case start, scanning, results }

    enum Tab: String, CaseIterable, Identifiable {
        case similar, blurry, dark, overexposed
        var id: String { rawValue }

        var issue: PhotoIssue? {
            switch self {
            case .similar:     nil
            case .blurry:      .blurry
            case .dark:        .dark
            case .overexposed: .overexposed
            }
        }

        var title: String { issue?.title ?? "Similar" }
    }

    private(set) var phase: Phase = .start
    var scope: PhotoScanner.Scope = .both
    var tab: Tab = .similar
    private(set) var result: PhotoScanResult = .empty
    private(set) var measured = 0
    private(set) var total = 0
    var selectedIDs: Set<String> = []
    var isConfirming = false
    private(set) var isRemoving = false
    var message: String?
    /// Set when the library was part of the scope but Photos access is off.
    private(set) var libraryAccessDenied = false

    /// The last folder photos moved to the Trash, so they can be put back.
    private(set) var lastMove: (trashed: [TrashedItem], previous: PhotoScanResult)?

    /// Called after files are moved, so the app can refresh its free-space figure.
    var onSpaceChanged: () -> Void = {}

    let home: URL
    /// False in demo mode, which must never read the real Photos library.
    let allowsLibrary: Bool
    private var task: Task<Void, Never>?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, allowsLibrary: Bool = true) {
        self.home = home
        self.allowsLibrary = allowsLibrary
        if !allowsLibrary { scope = .folders }
    }

    var scopes: [PhotoScanner.Scope] { allowsLibrary ? PhotoScanner.Scope.allCases : [.folders] }

    // MARK: Scan

    func scan() {
        guard !isRemoving else { return }
        task?.cancel()
        selectedIDs = []
        message = nil
        lastMove = nil
        isConfirming = false
        measured = 0
        total = 0
        libraryAccessDenied = false
        let scope = scope
        let folders = scope.includesFolders ? PhotoScanner.photoFolders(home: home) : []
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }

        task = Task {
            var includeLibrary = false
            if scope.includesLibrary && allowsLibrary {
                includeLibrary = await PhotosLibraryAccess.request()
                libraryAccessDenied = !includeLibrary
            }
            guard !Task.isCancelled else { return }
            let result = await PhotoScanner.scan(folders: folders, includeLibrary: includeLibrary) { done, total in
                Task { @MainActor in
                    self.measured = done
                    self.total = total
                }
            }
            guard !Task.isCancelled else { return }
            self.result = result
            self.tab = Self.firstTab(with: result)
            withAnimation(.easeOut(duration: 0.2)) { self.phase = .results }
        }
    }

    static func firstTab(with result: PhotoScanResult) -> Tab {
        Tab.allCases.first { count(in: $0, of: result) > 0 } ?? .similar
    }

    func cancelScan() {
        task?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func startOver() {
        task?.cancel()
        result = .empty
        selectedIDs = []
        message = nil
        lastMove = nil
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    var progress: Double? { total > 0 ? Double(measured) / Double(total) : nil }

    // MARK: Lists

    static func count(in tab: Tab, of result: PhotoScanResult) -> Int {
        if let issue = tab.issue { return result.photos(with: issue).count }
        return result.similar.count
    }

    func count(in tab: Tab) -> Int { Self.count(in: tab, of: result) }

    // MARK: Selection

    var selectedPhotos: [AnalyzedPhoto] {
        result.allPhotos.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 { selectedPhotos.compactMap(\.bytes).reduce(0, +) }

    func toggle(_ photo: AnalyzedPhoto) {
        if selectedIDs.contains(photo.id) { selectedIDs.remove(photo.id) } else { selectedIDs.insert(photo.id) }
    }

    /// Ticks every shot but the best in each similar group. Favourites stay unticked.
    func selectAllButBest() {
        for group in result.similar {
            for photo in group.photos.dropFirst() where !photo.isFavorite { selectedIDs.insert(photo.id) }
        }
    }

    func selectAll(_ issue: PhotoIssue) {
        selectedIDs.formUnion(result.photos(with: issue).map(\.id))
    }

    func deselectAll() { selectedIDs = [] }

    /// True when every shot of a group is ticked — worth a warning, since none would be left.
    func allSelected(_ group: SimilarGroup) -> Bool {
        group.photos.allSatisfy { selectedIDs.contains($0.id) }
    }

    // MARK: Remove

    var selectedLibraryCount: Int { selectedPhotos.filter(\.isInLibrary).count }
    var selectedFileCount: Int { selectedPhotos.count - selectedLibraryCount }

    /// Files go to the Trash; library photos go to Photos' Recently Deleted after Photos asks.
    func removeSelected() {
        let photos = selectedPhotos
        guard !photos.isEmpty, !isRemoving else { return }
        isConfirming = false
        isRemoving = true
        lastMove = nil
        let previous = result

        Task {
            var removed = Set<String>()
            var lines: [String] = []

            let files = photos.compactMap { photo in photo.fileURL.map { (photo.id, $0) } }
            if !files.isEmpty {
                let outcome = await FileActionService.shared.moveToTrash(paths: files.map(\.1.path))
                let failed = Set(outcome.errors.map(\.path))
                removed.formUnion(files.filter { !failed.contains($0.1.path) }.map(\.0))
                lastMove = outcome.trashed.isEmpty ? nil : (outcome.trashed, previous)
                lines.append(outcome.hasErrors
                    ? "Moved \(outcome.itemsRemoved) of \(files.count) photos to the Trash. Some couldn't be moved."
                    : "Moved \(outcome.itemsRemoved) \(outcome.itemsRemoved == 1 ? "photo" : "photos") (\(ByteSize.string(outcome.bytesFreed))) to the Trash.")
            }

            let library = photos.filter(\.isInLibrary)
            if !library.isEmpty {
                let identifiers = library.compactMap { photo -> String? in
                    if case .library(let identifier) = photo.location { return identifier }
                    return nil
                }
                do {
                    try await PhotosLibraryAccess.delete(identifiers)
                    removed.formUnion(library.map(\.id))
                    lines.append("Moved \(library.count) \(library.count == 1 ? "photo" : "photos") to Recently Deleted in Photos, where they stay for 30 days.")
                } catch {
                    lines.append("Photos in your library weren't removed.")
                }
            }

            result.remove(removed)
            selectedIDs.subtract(removed)
            isRemoving = false
            message = lines.joined(separator: " ")
            if !files.isEmpty { onSpaceChanged() }
        }
    }

    // MARK: Put Back

    var canPutBack: Bool { lastMove != nil }

    /// Moves the folder photos from the last removal back out of the Trash.
    func putBack() {
        guard let lastMove else { return }
        let outcome = PutBack.restore(lastMove.trashed)
        self.lastMove = nil
        let restored = Set(outcome.restored.map { "file:" + $0.original.path })
        var previous = lastMove.previous
        let gone = Set(previous.allPhotos.map(\.id)).subtracting(Set(result.allPhotos.map(\.id))).subtracting(restored)
        previous.remove(gone)
        result = previous
        message = outcome.failures.isEmpty
            ? "Put back \(outcome.restored.count) \(outcome.restored.count == 1 ? "photo" : "photos") from the Trash."
            : "Put back \(outcome.restored.count) of \(lastMove.trashed.count). \(outcome.failures[0])"
        onSpaceChanged()
    }

    func openPhotosSettings() {
        NSWorkspace.shared.open(PhotosLibraryAccess.settingsURL)
    }
}
