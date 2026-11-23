import SwiftUI

/// Drives the core flow: scan → review → confirm → clean → see what was freed.
@Observable
@MainActor
final class CleanUpViewModel {
    enum Phase: Equatable {
        case start
        case scanning
        case review
        case cleaning
        case done
    }

    private(set) var phase: Phase = .start
    private(set) var result: CleanupScanResult = .empty
    /// Groups that have finished scanning, for the live scanning list.
    private(set) var finishedGroups: [CleanupGroupKind: CleanupGroup] = [:]

    private(set) var selectedIDs: Set<String> = []
    /// Remembered per item even while unticked, so switching Erase/Delete isn't lost.
    private(set) var chosenActionIDs: [String: String] = [:]
    /// Missing means all entries when the parent is selected; an empty set selects none.
    private(set) var selectedEntryIDs: [String: Set<String>] = [:]

    var isConfirming = false

    private(set) var cleaningIndex = 0
    private(set) var cleaningTotal = 0
    private(set) var cleaningTitle = ""
    private(set) var report: CleanupReport?
    /// What happened when the user put Trash moves back, shown on the result screen.
    private(set) var putBackMessage: String?
    private(set) var isPuttingBack = false

    /// The user's Settings: re-download threshold, log age, Never Clean list.
    var settingsProvider: () -> CleanupSettings = { .standard }
    /// Called after a clean with its report: records history and refreshes free space.
    var onCleaned: (CleanupReport) -> Void = { _ in }
    /// Called when the user asks to always skip an item.
    var onAlwaysSkip: (CleanupItem) -> Void = { _ in }

    private let engine: any CleanupServicing
    private let restorer: any TrashRestoring
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var scanRevision = UUID()
    @ObservationIgnored private var resetWhenIdle = false
    @ObservationIgnored private var isRefreshingRunningApps = false

    isolated deinit { task?.cancel() }

    init(engine: any CleanupServicing, restorer: any TrashRestoring) {
        self.engine = engine
        self.restorer = restorer
    }

    // MARK: Scan

    func scan() {
        guard phase != .cleaning, !isPuttingBack else { return }
        task?.cancel()
        let revision = UUID()
        scanRevision = revision
        finishedGroups = [:]
        result = .empty
        report = nil
        // A confirmation left open (⌘R while it shows) must not reappear over the new results.
        isConfirming = false
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }

        let settings = settingsProvider()
        task = Task { [weak self, engine] in
            let result = await engine.scan(settings: settings) { [weak self] group in
                await MainActor.run { [weak self] in
                    // A stopped or replaced scan must not fill in the next one's list.
                    guard let self, self.scanRevision == revision, !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.finishedGroups[group.kind] = group
                    }
                }
            }
            guard let self, self.scanRevision == revision, !Task.isCancelled else { return }
            self.task = nil
            self.apply(result)
        }
    }

    func apply(_ result: CleanupScanResult) {
        self.result = result
        selectedIDs = Set(result.allItems.filter { $0.isRecommended && !$0.isBlocked }.map(\.id))
        chosenActionIDs = [:]
        selectedEntryIDs = [:]
        withAnimation(.easeOut(duration: 0.2)) { phase = .review }
    }

    func cancelScan() {
        guard phase == .scanning else { return }
        scanRevision = UUID()
        task?.cancel()
        task = nil
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    func refreshRunningApps() async {
        guard phase == .review, !isRefreshingRunningApps else { return }
        isRefreshingRunningApps = true
        defer { isRefreshingRunningApps = false }
        let revision = scanRevision
        let before = result
        let updated = await engine.refreshRunningApps(in: before)
        guard !Task.isCancelled, phase == .review, scanRevision == revision, result == before else { return }
        guard updated != result else { return }
        let blocked = Set(updated.allItems.filter(\.isBlocked).map(\.id))
        if !selectedIDs.isDisjoint(with: blocked) { isConfirming = false }
        selectedIDs.subtract(blocked)
        result = updated
    }

    // MARK: Selection

    var visibleGroups: [CleanupGroup] {
        result.groups.filter { !$0.items.isEmpty || !$0.notes.isEmpty }
    }

    func isSelected(_ item: CleanupItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    func setSelected(_ item: CleanupItem, _ selected: Bool) {
        guard phase == .review, result.allItems.first(where: { $0.id == item.id })?.isBlocked == false else { return }
        selectedEntryIDs.removeValue(forKey: item.id)
        if selected { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) }
    }

    func selectionState(for item: CleanupItem) -> SelectionState {
        guard isSelected(item) else { return .off }
        let entries = selectedEntries(for: item)
        return entries.count == item.inspectionEntries.count ? .on : .mixed
    }

    func toggle(_ item: CleanupItem) {
        setSelected(item, selectionState(for: item) != .on)
    }

    func selectedEntries(for item: CleanupItem) -> [CleanupEntry] {
        guard isSelected(item) else { return [] }
        let ids = selectedEntryIDs[item.id]
        let actionID = action(for: item).id
        return item.inspectionEntries.filter { (ids?.contains($0.id) ?? true) && $0.operations[actionID] != nil }
    }

    func isSelected(_ entry: CleanupEntry, in item: CleanupItem) -> Bool {
        isSelected(item) && (selectedEntryIDs[item.id]?.contains(entry.id) ?? true)
    }

    func setSelected(_ entry: CleanupEntry, in item: CleanupItem, _ selected: Bool) {
        guard phase == .review, result.allItems.first(where: { $0.id == item.id })?.isBlocked == false,
              item.inspectionEntries.contains(where: { $0.id == entry.id }),
              entry.operations[action(for: item).id] != nil else { return }
        var ids = Set(selectedEntries(for: item).map(\.id))
        if selected { ids.insert(entry.id) } else { ids.remove(entry.id) }
        selectedEntryIDs[item.id] = ids
        if ids.isEmpty { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
    }

    func selectedBytes(for item: CleanupItem) -> Int64 {
        guard isSelected(item) else { return 0 }
        if item.entries.isEmpty { return item.sizeBytes }
        return selectedEntries(for: item).reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    func action(for item: CleanupItem) -> CleanupAction {
        item.action(withID: chosenActionIDs[item.id])
    }

    func choose(_ action: CleanupAction, for item: CleanupItem) {
        chosenActionIDs[item.id] = action.id
    }

    func selectableItems(in group: CleanupGroup) -> [CleanupItem] {
        group.items.filter { !$0.isBlocked }
    }

    func setAll(in group: CleanupGroup, selected: Bool) {
        for item in selectableItems(in: group) {
            setSelected(item, selected)
        }
    }

    func selectionState(in group: CleanupGroup) -> SelectionState {
        let items = selectableItems(in: group)
        let selected = items.filter { selectedIDs.contains($0.id) }.count
        if selected == 0 { return .off }
        return selected == items.count && items.allSatisfy { selectionState(for: $0) == .on } ? .on : .mixed
    }

    func toggleAll(in group: CleanupGroup) {
        setAll(in: group, selected: selectionState(in: group) != .on)
    }

    func selectedCount(in group: CleanupGroup) -> Int {
        selectableItems(in: group).filter { selectedIDs.contains($0.id) }.count
    }

    func selectedBytes(in group: CleanupGroup) -> Int64 {
        selectableItems(in: group).reduce(0) { $0 + selectedBytes(for: $1) }
    }

    /// Groups the user folded away in the review list.
    var collapsedGroups: Set<CleanupGroupKind> = []

    func toggleCollapsed(_ kind: CleanupGroupKind) {
        if collapsedGroups.contains(kind) { collapsedGroups.remove(kind) } else { collapsedGroups.insert(kind) }
    }

    var selections: [CleanupSelection] {
        result.allItems
            .filter { selectedIDs.contains($0.id) && !$0.isBlocked }
            .flatMap { item in
                item.scopedSelections(entryIDs: Set(selectedEntries(for: item).map(\.id)), actionID: action(for: item).id)
            }
    }

    var selectedBytes: Int64 {
        selections.reduce(0) { $0 + $1.item.sizeBytes }
    }

    /// What will actually free space now (Trash moves don't until the Trash is emptied).
    var selectedFreeingBytes: Int64 {
        selections.filter { $0.action.regeneration.freesSpaceNow }.reduce(0) { $0 + $1.item.sizeBytes }
    }

    var selectionHasUpperBound: Bool {
        selections.contains { $0.item.sizeIsUpperBound }
    }

    var selectionHasUnknownSizes: Bool {
        selections.contains { $0.item.entries.contains { $0.sizeBytes == nil } }
    }

    var selectionSummary: String {
        let count = selections.count
        guard count > 0 else { return "Nothing selected" }
        let size = selectionHasUnknownSizes && selectedBytes == 0 ? "Size unavailable" : "\(selectionHasUpperBound ? "up to " : "")\(ByteSize.string(selectedBytes))"
        return "\(count) \(count == 1 ? "item" : "items") · \(size)\(selectionHasUnknownSizes && selectedBytes > 0 ? " + unmeasured" : "")"
    }

    // MARK: Clean

    func requestClean() {
        guard !selections.isEmpty else { return }
        isConfirming = true
    }

    func confirmClean() {
        // Only from review: a second Clean (double click, Return pressed twice while the sheet
        // closes) would start a second clean of the same items that Stop can't reach.
        guard phase == .review else { return }
        let selections = selections
        guard !selections.isEmpty else { return }
        isConfirming = false
        cleaningIndex = 0
        cleaningTotal = selections.count
        cleaningTitle = selections.first?.item.title ?? ""
        withAnimation(.easeOut(duration: 0.2)) { phase = .cleaning }

        let neverClean = settingsProvider().neverClean
        task = Task { [engine] in
            let report = await engine.clean(selections, neverClean: neverClean) { index, item in
                await MainActor.run {
                    withAnimation(.linear(duration: 0.15)) {
                        self.cleaningIndex = index
                        self.cleaningTitle = item.title
                    }
                }
            }
            self.finishCleaning(report)
        }
    }

    func finishCleaning(_ report: CleanupReport) {
        task = nil
        self.report = report
        putBackMessage = nil
        onCleaned(report)
        withAnimation(.easeOut(duration: 0.25)) { phase = .done }
        if resetWhenIdle { resetForNavigation() }
    }

    // MARK: Never Clean

    /// Adds the item to the Never Clean list and takes it out of this review.
    func alwaysSkip(_ item: CleanupItem) {
        onAlwaysSkip(item)
        selectedIDs.remove(item.id)
        selectedEntryIDs.removeValue(forKey: item.id)
        withAnimation(AppTheme.Motion.standard) {
            for index in result.groups.indices {
                result.groups[index].items.removeAll { $0.id == item.id }
            }
        }
    }

    // MARK: Put Back

    var canPutBack: Bool {
        !isPuttingBack && putBackMessage == nil && !(report?.trashedItems.isEmpty ?? true)
    }

    /// Moves everything this clean sent to the Trash back where it was.
    func putBack() {
        guard canPutBack, let items = report?.trashedItems, !items.isEmpty else { return }
        isPuttingBack = true
        Task {
            defer {
                isPuttingBack = false
                if resetWhenIdle { resetForNavigation() }
            }
            let outcome = await restorer.restore(items)
            let count = outcome.restored.count
            if outcome.failures.isEmpty {
                putBackMessage = "Put back \(count) \(count == 1 ? "item" : "items") from the Trash."
            } else {
                putBackMessage = "Put back \(count) of \(items.count). \(outcome.failures[0])"
            }
        }
    }

    /// Stops after the item in progress; the rest are reported as skipped.
    func stopCleaning() {
        task?.cancel()
    }

    func startOver() {
        guard phase != .cleaning, !isPuttingBack else { return }
        scanRevision = UUID()
        task?.cancel()
        task = nil
        result = .empty
        finishedGroups = [:]
        report = nil
        putBackMessage = nil
        selectedIDs = []
        chosenActionIDs = [:]
        selectedEntryIDs = [:]
        collapsedGroups = []
        isConfirming = false
        cleaningIndex = 0
        cleaningTotal = 0
        cleaningTitle = ""
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    /// A clean or restoration must finish before its report and recovery data are released.
    func resetForNavigation() {
        isConfirming = false
        guard phase != .cleaning, !isPuttingBack else {
            resetWhenIdle = true
            return
        }
        resetWhenIdle = false
        startOver()
    }

    var cleaningProgress: Double {
        guard cleaningTotal > 0 else { return 0 }
        return Double(cleaningIndex) / Double(cleaningTotal)
    }
}
