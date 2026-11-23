import AppKit
import SwiftUI

/// The complete scan snapshot for one item. Choices update the review immediately;
/// cleaning still goes through the main confirmation sheet.
struct CleanupItemDetailsSheet: View {
    @Bindable var model: CleanUpViewModel
    let item: CleanupItem
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var entries: [CleanupEntry] { item.inspectionEntries }
    private var visibleEntries: [CleanupEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedStandardContains(search) || ($0.detail?.localizedStandardContains(search) ?? false)
        }
    }
    private var selectionSummary: String {
        let selected = model.selectedEntries(for: item)
        let unknown = selected.contains { $0.sizeBytes == nil }
        let bytes = model.selectedBytes(for: item)
        let size = unknown && bytes == 0 ? "Size unavailable" : ByteSize.string(bytes) + (unknown ? " + unmeasured" : "")
        return "\(selected.count) of \(entries.count) selected · \(size)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(AppTheme.Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(selectionSummary)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .accessibilityIdentifier("cleanupEntrySelectionSummary")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .primaryAction()
                    .keyboardShortcut(.cancelAction)
            }
            HStack {
                RegenerationTag(regeneration: model.action(for: item).regeneration)
                Spacer()
                Button("Select All") { model.setSelected(item, true) }
                Button("Deselect All") { model.setSelected(item, false) }
            }
            .disabled(item.isBlocked)
            TextField("Search names and paths", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("cleanupEntrySearch")

            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.s) {
                    ForEach(visibleEntries) { entry in
                        entryRow(entry)
                    }
                    if visibleEntries.isEmpty {
                        Text("No matching entries")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
            if let blocked = item.blockedReason {
                InlineNote(text: blocked, symbolName: item.needsFullDiskAccess ? "lock" : "pause.circle")
            }
            if let warning = item.warning {
                InlineNote(text: warning, symbolName: "exclamationmark.triangle", tone: .warning)
            }
            if entries.count == 1, case .command = model.action(for: item).operation, item.entries.isEmpty {
                InlineNote(text: "This tool manages the cleanup as one operation.")
            }
        }
        .padding(AppTheme.Spacing.l)
        .frame(width: 620, height: 480)
        .background(AppTheme.Colors.canvas)
    }

    private func entryRow(_ entry: CleanupEntry) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            SelectionBox(state: model.isSelected(entry, in: item) ? .on : .off, isDisabled: item.isBlocked) {
                model.setSelected(entry, in: item, !model.isSelected(entry, in: item))
            }
            .accessibilityLabel("Select \(entry.title)")
            .accessibilityIdentifier("cleanupEntry.\(entry.id)")
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(AppTheme.Typography.headline)
                    .textSelection(.enabled)
                    .help(entry.detail ?? entry.title)
                if item.id != "general.appCaches", let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(detail)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
            if let bytes = entry.sizeBytes {
                SizeText(bytes: bytes, isUpperBound: item.sizeIsUpperBound)
            } else {
                Text("Size unavailable")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            if let url = entry.location {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .help("Show in Finder")
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 7)
    }
}
