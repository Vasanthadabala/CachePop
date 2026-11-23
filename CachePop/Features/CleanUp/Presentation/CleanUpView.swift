import SwiftUI

struct CleanUpView: View {
    @Bindable var model: CleanUpViewModel
    let disk: DiskInfo
    let history: CleanHistory
    @Binding var isShowingHistory: Bool

    var body: some View {
        // A stable container whose content cross-fades by phase. (A transition on a Group
        // left the screen blank when the section and the phase changed in the same instant.)
        ZStack {
            switch model.phase {
            case .start:
                CleanUpStartView(disk: disk, history: history, onScan: model.scan, onShowHistory: { isShowingHistory = true })
            case .scanning:
                CleanUpScanningView(model: model)
            case .review:
                CleanUpReviewView(model: model)
            case .cleaning:
                ProgressPanel(
                    title: "Cleaning \(model.cleaningTitle)…",
                    detail: "\(min(model.cleaningIndex + 1, model.cleaningTotal)) of \(model.cleaningTotal)",
                    progress: model.cleaningProgress,
                    cancelTitle: "Stop After This Item",
                    onCancel: model.stopCleaning
                )
            case .done:
                if let report = model.report {
                    CleanUpResultView(report: report, disk: disk, model: model, onDone: model.startOver)
                } else {
                    CleanUpStartView(disk: disk, history: history, onScan: model.scan, onShowHistory: { isShowingHistory = true })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppTheme.Motion.quick, value: model.phase)
        .sheet(isPresented: $isShowingHistory) {
            HistorySheet(history: history)
        }
    }
}

// MARK: - Start

private struct CleanUpStartView: View {
    let disk: DiskInfo
    let history: CleanHistory
    let onScan: () -> Void
    let onShowHistory: () -> Void

    var body: some View {
        let free = ByteSize.parts(disk.availableBytes)
        FeatureIntroScreen(
            points: CleanupGroupKind.allCases.map {
                FeatureIntroPoint(symbolName: $0.symbolName, title: $0.title, subtitle: $0.scanDescription)
            },
            pointsTitle: "What the scan covers"
        ) {
            FeatureIntroHeader(
                section: .cleanUp,
                caption: disk.volumeName,
                title: disk.totalBytes > 0 ? free.number : "—",
                unit: disk.totalBytes > 0 ? "\(free.unit) free" : nil,
                detail: disk.totalBytes > 0
                    ? "\(ByteSize.string(disk.usedBytes)) of \(ByteSize.string(disk.totalBytes)) used. Scan for space you can reclaim."
                    : "Scan for caches and files you can remove.",
                disk: disk
            ) {
                HStack(spacing: AppTheme.Spacing.m) {
                    Button(action: onScan) {
                        Label("Scan My Mac", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    if let last = history.lastClean {
                        HistorySummary(history: history, last: last, onShowHistory: onShowHistory)
                    }
                }
            }
        }
    }
}

/// "Freed 12.4 GB in 8 cleans · last 2 days ago · History"
private struct HistorySummary: View {
    let history: CleanHistory
    let last: CleanHistoryEntry
    let onShowHistory: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Freed \(ByteSize.string(history.lifetimeFreedBytes)) in \(history.records.count) \(history.records.count == 1 ? "clean" : "cleans")")
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Button("History", action: onShowHistory)
                .buttonStyle(.link)
        }
        .font(AppTheme.Typography.callout)
        .help("Last clean \(last.date.formatted(.relative(presentation: .named)))")
    }
}

// MARK: - Scanning

private struct CleanUpScanningView: View {
    let model: CleanUpViewModel

    private var foundSoFar: Int64 {
        model.finishedGroups.values.reduce(0) { $0 + $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(AppTheme.Spacing.xl)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
            }
            Button("Stop", action: model.cancelScan)
                .secondaryAction()
                .keyboardShortcut(.cancelAction)
                .padding(.vertical, AppTheme.Spacing.m)
        }
    }

    private var content: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            ZStack {
                // Each completed category fills one arc.
                ForEach(Array(CleanupGroupKind.allCases.enumerated()), id: \.element) { index, kind in
                    let count = Double(CleanupGroupKind.allCases.count)
                    let isDone = model.finishedGroups[kind] != nil
                    Circle()
                        .trim(from: Double(index) / count + 0.02, to: Double(index + 1) / count - 0.02)
                        .stroke(kind.hue.solid.opacity(isDone ? 1 : 0.25),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(AppTheme.Motion.standard, value: isDone)
                }
                VStack(spacing: 0) {
                    FigureText(bytes: foundSoFar, font: .system(size: 20, weight: .semibold, design: .rounded))
                    Text("found so far")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .frame(width: 120, height: 120)
            .padding(.bottom, AppTheme.Spacing.xs)

            VStack(spacing: 4) {
                Text("Scanning your Mac")
                    .font(AppTheme.Typography.largeTitle)
                Text("Measuring what's on disk. Nothing is changed.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(CleanupGroupKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { RowDivider(leadingInset: 48) }
                    ScanningRow(kind: kind, group: model.finishedGroups[kind])
                }
            }
            .card()
            .frame(maxWidth: 500)

        }
    }
}

private struct ScanningRow: View {
    let kind: CleanupGroupKind
    let group: CleanupGroup?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            IconTile(symbolName: kind.symbolName)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(AppTheme.Typography.headline)
                Text(kind.scanDescription)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Spacing.s)

            if let group {
                SizeText(bytes: group.totalBytes, emphasized: true)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.Status.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .frame(height: 46)
    }
}

// MARK: - Result

struct CleanUpResultView: View {
    let report: CleanupReport
    let disk: DiskInfo
    let model: CleanUpViewModel
    let onDone: () -> Void


    private var freedBytes: Int64 { report.measuredFreedBytes ?? report.estimatedFreedBytes }

    private var nothingRemoved: Bool {
        report.entries.allSatisfy {
            if case .removed = $0.outcome { return false }
            if case .movedToTrash = $0.outcome { return false }
            // A partly failed item still removed something (its size is in the freed figure).
            if case .failed(_, let removed) = $0.outcome, removed > 0 { return false }
            return true
        }
    }

    private var cleanedCount: Int {
        report.entries.count - report.skipped.count - report.failed.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.l) {
                hero
                    .padding(.top, AppTheme.Spacing.l)

                if model.canPutBack {
                    NoticeBanner(
                        text: "\(ByteSize.string(report.movedToTrashBytes)) went to the Trash. Changed your mind? Put it back where it was.",
                        tone: .info,
                        actionTitle: "Put Back",
                        action: model.putBack
                    )
                } else if let message = model.putBackMessage {
                    NoticeBanner(text: message, tone: .success)
                }

                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        ForEach(notes, id: \.self) { note in
                            InlineNote(text: note)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.xxs)
                }

                VStack(spacing: 0) {
                    CardHeader("What was cleaned", subtitle: summaryLine, symbolName: "checklist")
                    RowDivider(leadingInset: 0)
                    ForEach(Array(report.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider(leadingInset: 40) }
                        ResultRow(entry: entry)
                    }
                }
                .card()

            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
    }

    private var hero: some View {
        let freed = ByteSize.parts(freedBytes)
        let total = Double(max(disk.totalBytes, 1))
        let before = report.availableBefore.map { Double(disk.totalBytes - $0) / total }
        let now = Double(disk.usedBytes) / total
        return TapeHeader(
            caption: nothingRemoved ? "Nothing removed" : (report.measuredFreedBytes != nil ? "Done · measured from your disk" : "Done · estimated from file sizes"),
            value: freed.number,
            unit: "\(freed.unit) freed",
            tape: disk.totalBytes > 0 ? Tape(
                segments: [Tape.Segment(from: 0, to: now, color: AppTheme.Colors.accent)]
                    + (before.map { [Tape.Segment(from: now, to: max($0, now), color: AppTheme.Status.success, striped: true)] } ?? []),
                leading: report.availableBefore.map { "Before: \(ByteSize.string($0)) free" } ?? "0",
                center: report.movedToTrashBytes > 0 ? "\(ByteSize.string(report.movedToTrashBytes)) in the Trash" : nil,
                trailing: "Now: \(ByteSize.string(disk.availableBytes)) free"
            ) : nil,
            accessory: {
                Button(action: onDone) {
                    Text("Done").frame(minWidth: 120)
                }
                .primaryAction()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("cleanUpDone")
            }, visual: { EmptyView() }
        )
    }

    private var summaryLine: String {
        var parts = ["\(cleanedCount) cleaned"]
        if !report.skipped.isEmpty { parts.append("\(report.skipped.count) skipped") }
        if !report.failed.isEmpty { parts.append("\(report.failed.count) need attention") }
        return parts.joined(separator: " · ")
    }

    private var notes: [String] {
        var notes: [String] = []
        if report.movedToTrashBytes > 0 && model.putBackMessage == nil {
            notes.append("Space in the Trash is freed when you empty it.")
        }
        if let measured = report.measuredFreedBytes, report.estimatedFreedBytes > measured + 50_000_000 {
            notes.append("Listed sizes added up to \(ByteSize.string(report.estimatedFreedBytes)). Simulators and caches share some storage, so the measured figure is the real one.")
        }
        if let measured = report.measuredFreedBytes, measured + 50_000_000 < report.estimatedFreedBytes / 2 {
            notes.append("macOS can take a minute to hand back space after large deletions. The sidebar figure updates as it does.")
        }
        return notes
    }
}

private struct ResultRow: View {
    let entry: CleanupItemReport

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                Text(detail)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.Spacing.s)

            if bytes > 0 {
                SizeText(bytes: bytes, isUpperBound: entry.item.sizeIsUpperBound)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
        .hoverHighlight()
    }

    private var title: String {
        guard entry.item.actions.count > 1 else { return entry.item.title }
        let verb = entry.action.id == "erase" ? "erased" : "deleted"
        return "\(entry.item.title) — \(verb)"
    }

    private var bytes: Int64 {
        switch entry.outcome {
        case .removed(let bytes), .movedToTrash(let bytes): bytes
        case .failed(_, let removed): removed
        case .skipped: 0
        }
    }

    private var symbol: String {
        switch entry.outcome {
        case .removed:      "checkmark.circle.fill"
        case .movedToTrash: "trash.circle.fill"
        case .skipped:      "minus.circle.fill"
        case .failed:       "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch entry.outcome {
        case .removed, .movedToTrash: AppTheme.Status.success
        case .skipped:                AppTheme.Colors.textTertiary
        case .failed:                 AppTheme.Status.warning
        }
    }

    private var detail: String {
        switch entry.outcome {
        case .removed:                entry.action.regeneration.label + "."
        case .movedToTrash:           "Moved to the Trash."
        case .skipped(let reason):    "Skipped. \(reason)"
        case .failed(let message, _): message
        }
    }
}
