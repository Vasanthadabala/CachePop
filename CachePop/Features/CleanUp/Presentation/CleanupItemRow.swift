import AppKit
import SwiftUI

/// A compact item row with aligned totals and an optional preview of its entries.
struct CleanupItemRow: View {
    let model: CleanUpViewModel
    let item: CleanupItem
    let onViewAll: () -> Void
    @State private var isExpanded = false

    private var entries: [CleanupEntry] { item.inspectionEntries }
    private var state: SelectionState { model.selectionState(for: item) }
    private var showsEntryControls: Bool {
        item.group != .xcode && item.group != .simulators && item.group != .developerCaches
    }
    private var opensEntrySheet: Bool { item.group == .general || item.group == .browsers }
    private var showsEntryCount: Bool { item.group != .xcode && item.group != .developerCaches }
    private var visibleNote: String? {
        if item.group == .xcode, case .appBuild = item.inUseCheck { return nil }
        return item.note
    }
    private var actionID: Binding<String> {
        Binding(get: { model.action(for: item).id }, set: { id in
            model.choose(item.action(withID: id), for: item)
            model.setSelected(item, true)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if visibleNote != nil || item.warning != nil || item.blockedReason != nil {
                VStack(alignment: .leading, spacing: 5) {
                    if let note = visibleNote, !item.isBlocked {
                        InlineNote(text: note, symbolName: "arrow.down.circle")
                    }
                    if let warning = item.warning, !item.isBlocked {
                        InlineNote(text: warning, symbolName: "exclamationmark.triangle", tone: .warning)
                    }
                    if let blocked = item.blockedReason {
                        InlineNote(text: blocked, symbolName: item.needsFullDiskAccess ? "lock" : "pause.circle")
                    }
                }
                .padding(.leading, 90)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }

            if showsEntryControls && isExpanded {
                RowDivider(leadingInset: 58)
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider(leadingInset: 90) }
                        previewRow(entry)
                    }
                    HStack {
                        Text(entries.count > 4 ? "Showing 4 of \(entries.count) entries" : "\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Spacer()
                        viewAllButton
                    }
                    .padding(.leading, 90)
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
                }
                .background(AppTheme.Colors.hover)
            }
        }
        .opacity(item.isBlocked ? 0.6 : 1)
        .contextMenu {
            if case .appBuild(_, let path) = item.inUseCheck {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                Divider()
            }
            Button("Always Skip “\(item.title)”") { model.alwaysSkip(item) }
            Text("You can undo this in Settings › Never Clean.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Always Skip") { model.alwaysSkip(item) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            SelectionBox(state: state, isDisabled: item.isBlocked) { model.toggle(item) }
                .frame(width: 20, height: 24)
                .accessibilityLabel("Select \(item.title)")

            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppTheme.Colors.tile))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(AppTheme.Typography.headline)
                        .lineLimit(1)
                        .help(item.title)
                    RegenerationTag(regeneration: model.action(for: item).regeneration)
                        .layoutPriority(1)
                    if item.actions.count > 1 {
                        Picker("Action", selection: actionID) {
                            ForEach(item.actions) { action in Text(action.title).tag(action.id) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(item.isBlocked)
                    }
                }

                if item.group != .xcode && item.group != .general, let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(detail)
                }
                if state == .mixed {
                    Text("\(model.selectedEntries(for: item).count) of \(entries.count) selected")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { discloseEntries() }

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if showsEntryCount {
                        Text(item.needsFullDiskAccess ? "—" : "\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                    SizeText(bytes: item.sizeBytes, isUpperBound: item.sizeIsUpperBound, emphasized: state != .off)
                        .frame(width: 78, alignment: .trailing)
                    if showsEntryControls {
                        Button(action: discloseEntries) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .frame(width: 22, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("cleanupExpand.\(item.id)")
                        .accessibilityLabel(opensEntrySheet ? "View \(item.title) entries" : isExpanded ? "Hide \(item.title) entries" : "Preview \(item.title) entries")
                        .accessibilityValue(opensEntrySheet ? "" : isExpanded ? "Expanded" : "Collapsed")
                    }
                }
                if showsEntryControls && !opensEntrySheet && !isExpanded { viewAllButton }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var viewAllButton: some View {
        Button(action: onViewAll) {
            Pill(text: "View All", symbolName: "list.bullet")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cleanupViewAll.\(item.id)")
        .accessibilityLabel("View all \(item.title)")
    }

    private func previewRow(_ entry: CleanupEntry) -> some View {
        HStack(spacing: 12) {
            SelectionBox(state: model.isSelected(entry, in: item) ? .on : .off, isDisabled: item.isBlocked) {
                model.setSelected(entry, in: item, !model.isSelected(entry, in: item))
            }
            .frame(width: 20, height: 22)
            .accessibilityLabel("Select \(entry.title)")
            .accessibilityIdentifier("cleanupPreviewEntry.\(entry.id)")
            Text(entry.title)
                .font(AppTheme.Typography.callout)
                .lineLimit(1)
                .help(entry.detail ?? entry.title)
            Spacer(minLength: 8)
            if let bytes = entry.sizeBytes {
                SizeText(bytes: bytes, isUpperBound: item.sizeIsUpperBound)
            } else {
                Text("—")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .help("Size unavailable")
            }
        }
        .padding(.leading, 58)
        .padding(.trailing, 44)
        .padding(.vertical, 10)
        .hoverHighlight()
    }

    private func discloseEntries() {
        guard showsEntryControls else { return }
        if opensEntrySheet {
            onViewAll()
            return
        }
        withAnimation(AppTheme.Motion.quick) { isExpanded.toggle() }
    }

    private var symbolName: String {
        if item.id == "xcode.derivedData" { return "hammer" }
        if item.id.contains("deviceSupport") { return "iphone" }
        if item.id.contains("archives") { return "archivebox" }
        if item.id.lowercased().contains("cache") { return "clock.arrow.circlepath" }
        if item.id.lowercased().contains("log") { return "doc.text" }
        if item.id == "general.trash" { return "trash" }
        if item.id.contains("installers") || item.id.contains("Updates") { return "arrow.down.circle" }
        if item.id.contains("Snapshots") { return "clock.arrow.circlepath" }
        return item.group.symbolName
    }
}
