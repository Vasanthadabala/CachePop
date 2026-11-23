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
    var scope: PhotoScope = .both
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

    private let scanner: any PhotoScanning
    private let library: any PhotoLibraryManaging
    private let fileActions: any FileActionPerforming
    private let restorer: any TrashRestoring
    private let desktop: any DesktopInteracting
    private let clearThumbnails: () -> Void
    let home: URL
    /// False in demo mode, which must never read the real Photos library.
    let allowsLibrary: Bool
    private var task: Task<Void, Never>?
    @ObservationIgnored private var scanRevision = UUID()
    @ObservationIgnored private var resetWhenIdle = false

    init(home: URL, allowsLibrary: Bool, scanner: any PhotoScanning, library: any PhotoLibraryManaging,
         fileActions: any FileActionPerforming, restorer: any TrashRestoring,
         desktop: any DesktopInteracting, clearThumbnails: @escaping () -> Void) {
        self.home = home
        self.allowsLibrary = allowsLibrary
        self.scanner = scanner
        self.library = library
        self.fileActions = fileActions
        self.restorer = restorer
        self.desktop = desktop
        self.clearThumbnails = clearThumbnails
        if !allowsLibrary { scope = .folders }
    }

    isolated deinit { task?.cancel() }

    var scopes: [PhotoScope] { allowsLibrary ? PhotoScope.allCases : [.folders] }

    // MARK: Scan

    func scan() {
        guard !isRemoving else { return }
        task?.cancel()
        scanRevision = UUID()
        let revision = scanRevision
        result = .empty
        clearThumbnails()
        selectedIDs = []
        message = nil
        lastMove = nil
        isConfirming = false
        measured = 0
        total = 0
        libraryAccessDenied = false
        let scope = scope
        let folders = scope.includesFolders ? scanner.folders(home: home) : []
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }

        let allowsLibrary = allowsLibrary
        task = Task { [weak self, scanner, library] in
            var includeLibrary = false
            if scope.includesLibrary && allowsLibrary {
                includeLibrary = await library.requestAccess()
                guard let self, !Task.isCancelled, self.scanRevision == revision else { return }
                self.libraryAccessDenied = !includeLibrary
            }
            guard !Task.isCancelled else { return }
            let result = await scanner.scan(folders: folders, includeLibrary: includeLibrary) { [weak self] done, total in
                Task { @MainActor [weak self] in
                    guard let self, self.scanRevision == revision else { return }
                    self.measured = done
                    self.total = total
                }
            }
            guard let self, !Task.isCancelled, self.scanRevision == revision else { return }
            self.result = result
            self.tab = Self.firstTab(with: result)
            withAnimation(.easeOut(duration: 0.2)) { self.phase = .results }
        }
    }

    static func firstTab(with result: PhotoScanResult) -> Tab {
        Tab.allCases.first { count(in: $0, of: result) > 0 } ?? .similar
    }

    func cancelScan() {
        scanRevision = UUID()
        task?.cancel()
        task = nil
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func startOver() {
        guard !isRemoving else { return }
        scanRevision = UUID()
        task?.cancel()
        task = nil
        result = .empty
        clearThumbnails()
        selectedIDs = []
        message = nil
        lastMove = nil
        isConfirming = false
        measured = 0
        total = 0
        libraryAccessDenied = false
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func resetForNavigation() {
        isConfirming = false
        guard !isRemoving else {
            resetWhenIdle = true
            return
        }
        resetWhenIdle = false
        startOver()
        tab = .similar
        scope = allowsLibrary ? .both : .folders
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
            selectedIDs.formUnion(group.suggestedExtras.map(\.id))
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
            defer { finishRemoval() }
            var removed = Set<String>()
            var lines: [String] = []

            let files = photos.compactMap { photo in photo.fileURL.map { (photo.id, $0) } }
            if !files.isEmpty {
                let reviewed = Dictionary(photos.compactMap { photo -> (String, FileReviewIdentity)? in
                    guard let url = photo.fileURL, let identity = photo.identity else { return nil }
                    return (url.path, identity)
                }, uniquingKeysWith: { first, _ in first })
                let outcome = await fileActions.moveToTrash(paths: files.map(\.1.path), reviewed: reviewed)
                let failed = Set(outcome.errors.map(\.path))
                removed.formUnion(files.filter { !failed.contains($0.1.path) }.map(\.0))
                lastMove = outcome.trashed.isEmpty ? nil : (outcome.trashed, previous)
                lines.append(outcome.hasErrors
                    ? "Moved \(outcome.itemsRemoved) of \(files.count) photos to the Trash. Some couldn't be moved."
                    : "Moved \(outcome.itemsRemoved) \(outcome.itemsRemoved == 1 ? "photo" : "photos") (\(ByteSize.string(outcome.bytesFreed))) to the Trash.")
                if outcome.errors.contains(where: \.changedSinceScan) {
                    lines.append("Photos changed since the scan were kept. Check Photos again before removing them.")
                }
            }

            let library = photos.filter(\.isInLibrary)
            if !library.isEmpty {
                let identifiers = library.compactMap { photo -> String? in
                    if case .library(let identifier) = photo.location { return identifier }
                    return nil
                }
                do {
                    try await self.library.delete(identifiers)
                    removed.formUnion(library.map(\.id))
                    lines.append("Moved \(library.count) \(library.count == 1 ? "photo" : "photos") to Recently Deleted in Photos, where they stay for 30 days.")
                } catch {
                    lines.append("Photos in your library weren't removed.")
                }
            }

            result.remove(removed)
            selectedIDs.subtract(removed)
            message = lines.joined(separator: " ")
            if !files.isEmpty { onSpaceChanged() }
        }
    }

    // MARK: Put Back

    var canPutBack: Bool { lastMove != nil && !isRemoving }

    /// Moves the folder photos from the last removal back out of the Trash.
    func putBack() {
        guard !isRemoving, let lastMove else { return }
        isRemoving = true
        Task {
            defer { finishRemoval() }
            let outcome = await restorer.restore(lastMove.trashed)
            self.lastMove = nil
            let restored = Set(outcome.restored.map { "file:" + $0.original.path })
            var previous = lastMove.previous
            let gone = Set(previous.allPhotos.map(\.id)).subtracting(Set(result.allPhotos.map(\.id))).subtracting(restored)
            previous.remove(gone)
            previous.refreshRestoredIdentities(outcome.identities)
            result = previous
            message = outcome.failures.isEmpty
                ? "Put back \(outcome.restored.count) \(outcome.restored.count == 1 ? "photo" : "photos") from the Trash."
                : "Put back \(outcome.restored.count) of \(lastMove.trashed.count). \(outcome.failures[0])"
            onSpaceChanged()
        }
    }

    private func finishRemoval() {
        isRemoving = false
        if resetWhenIdle { resetForNavigation() }
    }

    func openPhotosSettings() {
        desktop.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
    }
}
