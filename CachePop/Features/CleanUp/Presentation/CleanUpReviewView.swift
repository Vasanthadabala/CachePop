import AppKit
import SwiftUI

/// The list of everything that can be freed, grouped, with sizes and recovery labels.
struct CleanUpReviewView: View {
    @Bindable var model: CleanUpViewModel
    @State private var inspectingItem: CleanupItem?

    var body: some View {
        Group {
            if model.result.allItems.isEmpty {
                EmptyStateView(
                    symbolName: "checkmark",
                    title: "Nothing to clean",
                    message: "No caches, developer leftovers, old logs or Trash were found."
                ) {
                    Button("Scan Again", action: model.scan)
                        .secondaryAction()
                }
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                            ReviewSummary(model: model)

                            if model.result.needsFullDiskAccess && !PermissionsManager.shared.hasFullDiskAccess {
                                PermissionPromptView(
                                    reason: "macOS keeps the Trash and device backups private, so CachePop can't see or clean them without access.",
                                    showsDetails: false
                                )
                            }

                            ForEach(model.visibleGroups) { group in
                                CleanupGroupSection(model: model, group: group) { inspectingItem = $0 }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.top, AppTheme.Spacing.m)
                        .padding(.bottom, 76)
                    }

                    ActionBarScrim()
                    CleanupSelectionBar(model: model)
                }
            }
        }
        .sheet(isPresented: $model.isConfirming) {
            ConfirmCleanSheet(model: model)
        }
        .sheet(item: $inspectingItem) { item in
            CleanupItemDetailsSheet(model: model, item: item)
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .review { inspectingItem = nil }
        }
        .onChange(of: model.result) { _, result in
            if let item = inspectingItem { inspectingItem = result.allItems.first { $0.id == item.id } }
        }
        .task { await model.refreshRunningApps() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            Task { await model.refreshRunningApps() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            Task { await model.refreshRunningApps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshRunningApps() }
        }
    }
}

// MARK: - Summary

private struct ReviewSummary: View {
    let model: CleanUpViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
            HStack(spacing: AppTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose what to clean")
                        .font(.system(size: 21, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ByteSize.string(model.result.reclaimableBytes))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.accent)
                        Text("found across \(model.result.allItems.count) cleanup items")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Button(action: model.scan) {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .secondaryAction()
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                BreakdownBar(segments: segments, showsUnselectedColors: true)
                FlowLayout(spacing: AppTheme.Spacing.l, lineSpacing: AppTheme.Spacing.xs) {
                    ForEach(segments.filter { $0.total > 0 }) { segment in
                        LegendItem(segment: segment)
                            .accessibilityElement(children: .combine)
                            .help("\(ByteSize.string(segment.selected)) selected in \(segment.title)")
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.l)
        .card()
        .animation(AppTheme.Motion.standard, value: model.selectedBytes)
    }

    private var segments: [BreakdownSegment] {
        // Favor the primary colors, then gray, and keep the extra purple category last.
        let order: [CleanupGroupKind] = [.xcode, .simulators, .developerCaches, .general, .devices, .browsers, .leftovers]
        return order.compactMap { kind in model.result.groups.first { $0.kind == kind } }.map { group in
            BreakdownSegment(id: group.kind.id, title: group.kind.title, color: group.kind.hue.solid,
                             total: group.totalBytes, selected: model.selectedBytes(in: group))
        }
    }

}

private struct CleanupSelectionBar: View {
    let model: CleanUpViewModel

    var body: some View {
        let parts = ByteSize.parts(model.selectedBytes)
        let unknown = model.selectionHasUnknownSizes && model.selectedBytes == 0
        HStack(spacing: AppTheme.Spacing.m) {
            HStack(spacing: AppTheme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(unknown ? "—" : parts.number)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if !unknown {
                        Text(parts.unit)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .foregroundStyle(model.selections.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
                Rectangle()
                    .fill(AppTheme.Colors.separator)
                    .frame(width: 1, height: 20)
                Text(model.selections.isEmpty ? "Nothing selected" : "\(model.selections.count) selected")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.selectionSummary)
            Spacer(minLength: 8)
            if model.selectionHasUpperBound || model.selectionHasUnknownSizes {
                Text(unknown ? "Size unavailable" : "Estimated")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Button(action: model.requestClean) {
                HStack(spacing: 8) {
                    Text("Clean…")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .primaryAction()
            .accessibilityLabel("Clean…")
            .keyboardShortcut(.defaultAction)
            .disabled(model.selections.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(radius: AppTheme.Radius.bar, raised: true)
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.m)
        .animation(AppTheme.Motion.quick, value: model.selectedBytes)
    }
}

// MARK: - Group

private struct CleanupGroupSection: View {
    let model: CleanUpViewModel
    let group: CleanupGroup
    let onViewAll: (CleanupItem) -> Void

    private var isCollapsed: Bool { model.collapsedGroups.contains(group.kind) }
    private var selectableCount: Int { model.selectableItems(in: group).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if !isCollapsed {
                if !group.items.isEmpty {
                    RowDivider(leadingInset: 0)
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider(leadingInset: 90) }
                            CleanupItemRow(model: model, item: item) { onViewAll(item) }
                        }
                    }
                }
                if !group.notes.isEmpty {
                    RowDivider(leadingInset: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.notes, id: \.self) { note in
                            InlineNote(text: note)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            SelectionBox(state: model.selectionState(in: group), isDisabled: selectableCount == 0) {
                withAnimation(AppTheme.Motion.quick) { model.toggleAll(in: group) }
            }
            .help("Select or deselect everything in \(group.kind.title)")

            Image(systemName: group.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.kind.title)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: AppTheme.Spacing.s)

            if group.totalBytes > 0 {
                SizeText(bytes: group.totalBytes, emphasized: true)
            }

            Button {
                withAnimation(AppTheme.Motion.standard) { model.toggleCollapsed(group.kind) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(AppTheme.Colors.tile))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show items" : "Hide items")
            .accessibilityIdentifier("cleanupGroupDisclosure.\(group.kind.id)")
            .accessibilityLabel("\(isCollapsed ? "Show" : "Hide") \(group.kind.title) items")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.hover)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if group.items.isEmpty { return "Nothing found" }
        if selectableCount == 0 { return "\(group.items.count) found · in use right now" }
        let selected = model.selectedCount(in: group)
        guard selected > 0 else { return "\(selectableCount) found · none selected" }
        return "\(selected) of \(selectableCount) selected · \(ByteSize.string(model.selectedBytes(in: group)))"
    }
}

// MARK: - Confirmation

/// Says exactly what will happen, grouped by whether it comes back, before anything runs.
struct ConfirmCleanSheet: View {
    let model: CleanUpViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var listHeight: CGFloat = 380

    private var buckets: [(Regeneration, [CleanupEngine.Selection])] {
        let order: [Regeneration] = [.permanent, .movedToTrash, .automatic, .redownloaded, .onDeviceConnect, .unusable]
        let grouped = Dictionary(grouping: model.selections) { $0.action.regeneration }
        return order.compactMap { regeneration in
            guard let items = grouped[regeneration], !items.isEmpty else { return nil }
            return (regeneration, items)
        }
    }

    private var hasPermanent: Bool {
        model.selections.contains { $0.action.regeneration == .permanent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                IconTile(symbolName: "trash", size: 36, tone: .accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean \(model.selections.count) \(model.selections.count == 1 ? "item" : "items")?")
                        .font(AppTheme.Typography.title)
                    Text(summary)
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppTheme.Spacing.l)

            RowDivider(leadingInset: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    ForEach(buckets, id: \.0) { regeneration, selections in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            RegenerationTag(regeneration: regeneration)
                            VStack(spacing: 0) {
                                ForEach(Array(selections.enumerated()), id: \.element.item.id) { index, selection in
                                    if index > 0 { RowDivider(leadingInset: AppTheme.Spacing.s) }
                                    ConfirmRow(selection: selection)
                                }
                            }
                            .card(radius: AppTheme.Radius.medium + 2)
                        }
                    }
                }
                .padding(AppTheme.Spacing.l)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, 380))

            RowDivider(leadingInset: 0)

            HStack {
                if hasPermanent {
                    InlineNote(text: "Items marked “Doesn't come back” can't be restored.", symbolName: "exclamationmark.triangle", tone: .warning)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .secondaryAction()
                    .keyboardShortcut(.cancelAction)
                Button("Clean") { model.confirmClean() }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppTheme.Spacing.l)
        }
        .frame(width: 480)
        .background(AppTheme.Colors.canvas)
    }

    private var summary: String {
        var parts = model.selectionHasUnknownSizes && model.selectedBytes == 0
            ? ["The size of the selected entries is unavailable."]
            : ["\(model.selectionHasUpperBound ? "Up to " : "About ")\(ByteSize.string(model.selectedFreeingBytes)) will be freed."]
        if model.selectionHasUnknownSizes && model.selectedBytes > 0 {
            parts.append("Some selected entries have no individual size estimate.")
        }
        let trashBytes = model.selectedBytes - model.selectedFreeingBytes
        if trashBytes > 0 {
            parts.append("\(ByteSize.string(trashBytes)) goes to the Trash.")
        }
        parts.append("CachePop measures the real amount from your disk afterwards.")
        return parts.joined(separator: " ")
    }
}

private struct ConfirmRow: View {
    let selection: CleanupEngine.Selection

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.xs) {
            Text(selection.item.actions.count > 1 ? "\(selection.action.title) \(selection.item.title)" : selection.item.title)
                .font(AppTheme.Typography.body)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppTheme.Spacing.s)
            SizeText(bytes: selection.item.sizeBytes, isUpperBound: selection.item.sizeIsUpperBound)
        }
        .padding(.horizontal, AppTheme.Spacing.s)
        .padding(.vertical, 7)
    }
}
