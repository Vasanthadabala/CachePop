import SwiftUI

@Observable
@MainActor
final class LargeFilesViewModel {
    enum Phase { case start, scanning, results }

    enum Tab: String, CaseIterable, Identifiable {
        case large
        case duplicates
        var id: String { rawValue }
    }

    private(set) var phase: Phase = .start
    var tab: Tab = .large
    /// nil means the standard home folders.
    private(set) var chosenFolder: URL?
    private(set) var result: LargeFilesResult = .empty {
        didSet { reviewBytes = result.reviewBytes }
    }
    private(set) var reviewBytes: Int64 = 0
    private(set) var currentPath = ""
    var selectedIDs: Set<String> = []
    var isConfirming = false
    private(set) var isMoving = false
    var message: String?

    /// Filters for the large files list.
    var kindFilter: FileKind?
    var ageFilter: FileAge = .any
    /// The file Quick Look shows; nil when it's closed.
    var previewURL: URL?
    /// The row last clicked, which Space previews.
    var currentFileID: String?

    /// The last move to the Trash, so it can be put back.
    private(set) var lastMove: (trashed: [TrashedItem], previous: LargeFilesResult)?

    /// Called after files are moved, so the app can refresh its free-space figure.
    var onSpaceChanged: () -> Void = {}

    private let classifier: any FileClassifying
    private let scanner: any LargeFilesScanning
    private let fileActions: any FileActionPerforming
    private let restorer: any TrashRestoring
    private let desktop: any DesktopInteracting
    let home: URL
    private let settings: (any LargeFilePreferencesProviding)?
    private var task: Task<Void, Never>?
    @ObservationIgnored private var scanRevision = UUID()
    @ObservationIgnored private var resetWhenIdle = false

    init(home: URL, settings: (any LargeFilePreferencesProviding)?, scanner: any LargeFilesScanning, classifier: any FileClassifying,
         fileActions: any FileActionPerforming, restorer: any TrashRestoring, desktop: any DesktopInteracting) {
        self.home = home
        self.settings = settings
        self.scanner = scanner
        self.classifier = classifier
        self.fileActions = fileActions
        self.restorer = restorer
        self.desktop = desktop
    }

    isolated deinit { task?.cancel() }

    /// Folders from Settings, or the standard home folders.
    private var defaultRoots: [URL] {
        let chosen = (settings?.largeFileFolders ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        // An unavailable custom folder must not silently widen the scan to personal folders.
        return chosen.isEmpty ? scanner.defaultRoots(home: home) : chosen
    }

    var thresholdBytes: Int64 { settings?.largeFileThreshold ?? LargeFilePolicy.defaultThreshold }

    /// "100 MB", for "Anything over 100 MB".
    var thresholdDescription: String {
        let megabytes = Int(thresholdBytes / 1_048_576)
        return megabytes >= 1024 ? "\(megabytes / 1024) GB" : "\(megabytes) MB"
    }

    var defaultScopeTitle: String {
        let folders = settings?.largeFileFolders ?? []
        guard let first = folders.first else { return "Home Folders" }
        return folders.count == 1 ? URL(fileURLWithPath: first).lastPathComponent : "\(folders.count) folders"
    }

    var scopeName: String {
        if let chosenFolder { return "“\(chosenFolder.lastPathComponent)”" }
        let folders = settings?.largeFileFolders ?? []
        guard !folders.isEmpty else { return "Desktop, Documents, Downloads, Movies, Music, Pictures and Public" }
        return folders.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
    }

    func chooseFolder() {
        if let url = desktop.chooseFolder(startingAt: chosenFolder ?? home,
                                          message: "Choose a folder to look for large and duplicate files.") {
            chosenFolder = url
        }
    }

    func useHomeFolders() {
        chosenFolder = nil
    }

    func scan() {
        // A move still running would land its results, and a Put Back of the old list, on top
        // of the new scan.
        guard !isMoving else { return }
        task?.cancel()
        scanRevision = UUID()
        let revision = scanRevision
        result = .empty
        previewURL = nil
        currentFileID = nil
        selectedIDs = []
        message = nil
        currentPath = ""
        lastMove = nil
        // A confirmation left open (⌘R while it shows) must not reappear over the new results.
        isConfirming = false
        let roots = chosenFolder.map { [$0] } ?? defaultRoots
        let threshold = thresholdBytes
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }

        task = Task { [weak self, scanner] in
            let result = await scanner.scan(roots: roots, threshold: threshold) { [weak self] path in
                Task { @MainActor [weak self] in
                    guard let self, self.scanRevision == revision else { return }
                    self.currentPath = path
                }
            }
            guard let self, !Task.isCancelled, self.scanRevision == revision else { return }
            self.result = result
            self.tab = result.largeFiles.isEmpty && !result.duplicates.isEmpty ? .duplicates : .large
            withAnimation(.easeOut(duration: 0.2)) { self.phase = .results }
        }
    }

    func cancelScan() {
        scanRevision = UUID()
        task?.cancel()
        task = nil
        currentPath = ""
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func startOver() {
        guard !isMoving else { return }
        scanRevision = UUID()
        task?.cancel()
        task = nil
        result = .empty
        lastMove = nil
        previewURL = nil
        currentFileID = nil
        currentPath = ""
        selectedIDs = []
        message = nil
        isConfirming = false
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func resetForNavigation() {
        isConfirming = false
        guard !isMoving else {
            resetWhenIdle = true
            return
        }
        resetWhenIdle = false
        startOver()
        tab = .large
        chosenFolder = nil
        kindFilter = nil
        ageFilter = .any
    }

    // MARK: Filters and preview

    var filteredLargeFiles: [FoundFile] {
        result.largeFiles.filter { file in
            (kindFilter == nil || classifier.kind(of: file.url) == kindFilter) && ageFilter.includes(file)
        }
    }

    /// Every file Quick Look can step through with the arrow keys.
    var previewableURLs: [URL] {
        (filteredLargeFiles + result.duplicates.flatMap(\.files)).map(\.url)
    }

    func count(of kind: FileKind) -> Int {
        result.largeFiles.filter { classifier.kind(of: $0.url) == kind }.count
    }

    func preview(_ file: FoundFile) {
        currentFileID = file.id
        previewURL = file.url
    }

    /// Space: preview the row last clicked, or close the preview.
    func togglePreview() {
        if previewURL != nil {
            previewURL = nil
        } else if let id = currentFileID, let file = allFiles.first(where: { $0.id == id }) {
            previewURL = file.url
        } else if let first = filteredLargeFiles.first {
            preview(first)
        }
    }

    // MARK: Selection

    private var allFiles: [FoundFile] {
        result.largeFiles + result.duplicates.flatMap(\.files)
    }

    var selectedFiles: [FoundFile] {
        var seen = Set<String>()
        return allFiles.filter { selectedIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func toggle(_ file: FoundFile) {
        currentFileID = file.id
        if selectedIDs.contains(file.id) { selectedIDs.remove(file.id) } else { selectedIDs.insert(file.id) }
    }

    /// Ticks every copy except the newest in each duplicate set.
    func selectExtraCopies() {
        for set in result.duplicates {
            for file in set.files.dropFirst() { selectedIDs.insert(file.id) }
        }
    }

    /// True when every copy of a set is ticked — worth a warning, since nothing would remain.
    func allCopiesSelected(_ set: DuplicateSet) -> Bool {
        set.files.allSatisfy { selectedIDs.contains($0.id) }
    }

    // MARK: Trash

    func moveSelectedToTrash() {
        let files = selectedFiles
        guard !files.isEmpty, !isMoving else { return }
        isConfirming = false
        isMoving = true

        let previous = result
        Task {
            defer { finishMove() }
            let reviewed = Dictionary(files.compactMap { file in file.identity.map { (file.url.path, $0) } },
                                      uniquingKeysWith: { first, _ in first })
            let outcome = await fileActions.moveToTrash(paths: files.map(\.url.path), reviewed: reviewed)
            lastMove = outcome.trashed.isEmpty ? nil : (outcome.trashed, previous)
            let moved = Set(files.map(\.id)).subtracting(outcome.errors.map(\.path))
            result.largeFiles.removeAll { moved.contains($0.id) }
            result.duplicates = result.duplicates.compactMap { set in
                let remaining = set.files.filter { !moved.contains($0.id) }
                return remaining.count > 1 ? DuplicateSet(id: set.id, files: remaining) : nil
            }
            selectedIDs.subtract(moved)

            if outcome.hasErrors {
                message = "Moved \(outcome.itemsRemoved) of \(files.count) files to the Trash. Some couldn't be moved — they may be in use or protected."
            } else {
                message = "Moved \(outcome.itemsRemoved) \(outcome.itemsRemoved == 1 ? "file" : "files") (\(ByteSize.string(outcome.bytesFreed))) to the Trash. Empty the Trash to free the space."
            }
            if outcome.errors.contains(where: \.changedSinceScan) {
                message = "Moved \(outcome.itemsRemoved) of \(files.count) files. Files changed since the scan were kept. Scan again before removing them."
            }
            onSpaceChanged()
        }
    }

    // MARK: Put Back

    var canPutBack: Bool { lastMove != nil && !isMoving }

    /// Moves the files from the last Trash move back, and lists them again.
    func putBack() {
        guard !isMoving, let lastMove else { return }
        isMoving = true
        Task {
            defer { finishMove() }
            let outcome = await restorer.restore(lastMove.trashed)
            self.lastMove = nil
            let restored = Set(outcome.restored.map(\.original.path))
            let current = Set(result.largeFiles.map(\.id) + result.duplicates.flatMap(\.files).map(\.id))
            func refreshed(_ file: FoundFile) -> FoundFile {
                guard let identity = outcome.identities[file.url.path] else { return file }
                var updated = file
                updated.identity = identity
                return updated
            }
            // Show what was there before, minus anything that couldn't come back.
            var previous = lastMove.previous
            previous.largeFiles = previous.largeFiles.compactMap {
                restored.contains($0.id) || current.contains($0.id) ? refreshed($0) : nil
            }
            previous.duplicates = previous.duplicates.compactMap { set in
                let files = set.files.compactMap {
                    restored.contains($0.id) || current.contains($0.id) ? refreshed($0) : nil
                }
                return files.count > 1 ? DuplicateSet(id: set.id, files: files) : nil
            }
            result = previous
            message = outcome.failures.isEmpty
                ? "Put back \(outcome.restored.count) \(outcome.restored.count == 1 ? "file" : "files") from the Trash."
                : "Put back \(outcome.restored.count) of \(lastMove.trashed.count). \(outcome.failures[0])"
            onSpaceChanged()
        }
    }

    private func finishMove() {
        isMoving = false
        if resetWhenIdle { resetForNavigation() }
    }
}
