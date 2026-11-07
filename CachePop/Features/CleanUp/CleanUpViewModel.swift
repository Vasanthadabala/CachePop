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

    var isConfirming = false

    private(set) var cleaningIndex = 0
    private(set) var cleaningTotal = 0
    private(set) var cleaningTitle = ""
    private(set) var report: CleanupReport?
    /// What happened when the user put Trash moves back, shown on the result screen.
    private(set) var putBackMessage: String?

    /// The user's Settings: re-download threshold, log age, Never Clean list.
    var settingsProvider: () -> CleanupSettings = { .standard }
    /// Called after a clean with its report: records history and refreshes free space.
    var onCleaned: (CleanupReport) -> Void = { _ in }
    /// Called when the user asks to always skip an item.
    var onAlwaysSkip: (CleanupItem) -> Void = { _ in }

    private let engine: CleanupEngine
    private var task: Task<Void, Never>?

    init(engine: CleanupEngine = CleanupEngine()) {
        self.engine = engine
    }

    // MARK: Scan

    func scan() {
        task?.cancel()
        finishedGroups = [:]
        result = .empty
        report = nil
        // A confirmation left open (⌘R while it shows) must not reappear over the new results.
        isConfirming = false
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }

        let settings = settingsProvider()
        task = Task { [engine] in
            let result = await engine.scan(settings: settings) { group in
                await MainActor.run {
                    // A stopped or replaced scan must not fill in the next one's list.
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.finishedGroups[group.kind] = group
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self.apply(result)
        }
    }

    func apply(_ result: CleanupScanResult) {
        self.result = result
        selectedIDs = Set(result.allItems.filter { $0.isRecommended && !$0.isBlocked }.map(\.id))
        chosenActionIDs = [:]
        withAnimation(.easeOut(duration: 0.2)) { phase = .review }
    }

    func cancelScan() {
        task?.cancel()
        task = nil
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    // MARK: Selection

    var visibleGroups: [CleanupGroup] {
        result.groups.filter { !$0.items.isEmpty || !$0.notes.isEmpty }
    }

    func isSelected(_ item: CleanupItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    func setSelected(_ item: CleanupItem, _ selected: Bool) {
        guard !item.isBlocked else { return }
        if selected { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) }
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
        return selected == items.count ? .on : .mixed
    }

    func toggleAll(in group: CleanupGroup) {
        setAll(in: group, selected: selectionState(in: group) != .on)
    }

    func selectedCount(in group: CleanupGroup) -> Int {
        selectableItems(in: group).filter { selectedIDs.contains($0.id) }.count
    }

    func selectedBytes(in group: CleanupGroup) -> Int64 {
        selectableItems(in: group).filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Groups the user folded away in the review list.
    var collapsedGroups: Set<CleanupGroupKind> = []

    func toggleCollapsed(_ kind: CleanupGroupKind) {
        if collapsedGroups.contains(kind) { collapsedGroups.remove(kind) } else { collapsedGroups.insert(kind) }
    }

    var selections: [CleanupEngine.Selection] {
        result.allItems
            .filter { selectedIDs.contains($0.id) && !$0.isBlocked }
            .map { CleanupEngine.Selection(item: $0, action: action(for: $0)) }
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

    var selectionSummary: String {
        let count = selections.count
        guard count > 0 else { return "Nothing selected" }
        return "\(count) \(count == 1 ? "item" : "items") · \(selectionHasUpperBound ? "up to " : "")\(ByteSize.string(selectedBytes))"
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
        self.report = report
        putBackMessage = nil
        onCleaned(report)
        withAnimation(.easeOut(duration: 0.25)) { phase = .done }
    }

    // MARK: Never Clean

    /// Adds the item to the Never Clean list and takes it out of this review.
    func alwaysSkip(_ item: CleanupItem) {
        onAlwaysSkip(item)
        selectedIDs.remove(item.id)
        withAnimation(AppTheme.Motion.standard) {
            for index in result.groups.indices {
                result.groups[index].items.removeAll { $0.id == item.id }
            }
        }
    }

    // MARK: Put Back

    var canPutBack: Bool {
        putBackMessage == nil && !(report?.trashedItems.isEmpty ?? true)
    }

    /// Moves everything this clean sent to the Trash back where it was.
    func putBack() {
        guard let items = report?.trashedItems, !items.isEmpty else { return }
        let outcome = PutBack.restore(items)
        let count = outcome.restored.count
        if outcome.failures.isEmpty {
            putBackMessage = "Put back \(count) \(count == 1 ? "item" : "items") from the Trash."
        } else {
            putBackMessage = "Put back \(count) of \(items.count). \(outcome.failures[0])"
        }
    }

    /// Stops after the item in progress; the rest are reported as skipped.
    func stopCleaning() {
        task?.cancel()
    }

    func startOver() {
        task?.cancel()
        task = nil
        result = .empty
        report = nil
        putBackMessage = nil
        selectedIDs = []
        chosenActionIDs = [:]
        withAnimation(.easeOut(duration: 0.2)) { phase = .start }
    }

    var cleaningProgress: Double {
        guard cleaningTotal > 0 else { return 0 }
        return Double(cleaningIndex) / Double(cleaningTotal)
    }
}
