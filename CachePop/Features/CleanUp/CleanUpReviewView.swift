import SwiftUI

/// The list of everything that can be freed, grouped, with sizes and plain explanations.
struct CleanUpReviewView: View {
    @Bindable var model: CleanUpViewModel

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
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                            ReviewSummary(model: model)

                            if model.result.needsFullDiskAccess && !PermissionsManager.shared.hasFullDiskAccess {
                                PermissionPromptView(reason: "macOS keeps the Trash and device backups private, so CachePop can't see or clean them without access.")
                            }

                            ForEach(model.visibleGroups) { group in
                                GroupCard(model: model, group: group)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.top, AppTheme.Spacing.m)
                        .clearsActionBar()
                    }

                    FloatingActionBar(
                        summary: model.selectionSummary,
                        detail: model.selections.isEmpty
                            ? "Tick what you want to remove."
                            : "You'll see exactly what happens before anything is removed."
                    ) {
                        Button(action: model.requestClean) {
                            Text("Clean…").frame(minWidth: 72)
                        }
                        .primaryAction()
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.selections.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $model.isConfirming) {
            ConfirmCleanSheet(model: model)
        }
    }
}

// MARK: - Summary

private struct ReviewSummary: View {
    let model: CleanUpViewModel

    var body: some View {
        let selected = ByteSize.parts(model.selectedBytes)
        TapeHeader(
            caption: "Selected to clean",
            value: selected.number,
            unit: selected.unit,
            detail: "of \(ByteSize.string(model.result.reclaimableBytes)) found in \(model.result.allItems.count) places"
        ) {
            Button {
                model.scan()
            } label: {
                Label("Scan Again", systemImage: "arrow.clockwise")
            }
            .controlSize(.regular)
        } visual: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                BreakdownBar(segments: segments)
                FlowLayout(spacing: AppTheme.Spacing.m, lineSpacing: AppTheme.Spacing.xs) {
                    ForEach(segments.filter { $0.total > 0 }) { segment in
                        LegendItem(segment: segment)
                    }
                }
                Text("Coloured is what's selected, grey isn't. Ticked items come back on their own or download again when needed; nothing is removed until you confirm.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(AppTheme.Motion.standard, value: model.selectedBytes)
    }

    private var segments: [BreakdownSegment] {
        model.result.groups.map { group in
            BreakdownSegment(
                id: group.kind.rawValue,
                title: group.kind.title,
                color: group.kind.hue.solid,
                total: group.totalBytes,
                selected: model.selectedBytes(in: group)
            )
        }
    }
}

// MARK: - Group

private struct GroupCard: View {
    let model: CleanUpViewModel
    let group: CleanupGroup

    private var isCollapsed: Bool { model.collapsedGroups.contains(group.kind) }
    private var selectableCount: Int { model.selectableItems(in: group).count }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !isCollapsed {
                if !group.items.isEmpty {
                    RowDivider(leadingInset: 0)
                }
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider(leadingInset: 36) }
                    CleanupItemRow(model: model, item: item)
                }
                if !group.notes.isEmpty {
                    RowDivider(leadingInset: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.notes, id: \.self) { note in
                            InlineNote(text: note)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, AppTheme.Spacing.s)
                }
            }
        }
        .card()
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            SelectionBox(state: model.selectionState(in: group), isDisabled: selectableCount == 0) {
                withAnimation(AppTheme.Motion.quick) { model.toggleAll(in: group) }
            }
            .help("Select or deselect everything in \(group.kind.title)")

            IconTile(symbolName: group.kind.symbolName, size: 28, hue: group.kind.hue)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.kind.title)
                    .font(AppTheme.Typography.title2)
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
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 10)
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

// MARK: - Row

private struct CleanupItemRow: View {
    let model: CleanUpViewModel
    let item: CleanupItem

    private var isSelected: Bool { model.isSelected(item) }

    private var actionID: Binding<String> {
        Binding(
            get: { model.action(for: item).id },
            set: { id in
                model.choose(item.action(withID: id), for: item)
                model.setSelected(item, true)
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            SelectionBox(state: isSelected ? .on : .off, isDisabled: item.isBlocked) {
                model.setSelected(item, !isSelected)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                    Text(item.title)
                        .font(AppTheme.Typography.headline)
                        .lineLimit(1)

                    if item.actions.count > 1 {
                        Picker("Action", selection: actionID) {
                            ForEach(item.actions) { action in
                                Text(action.title).tag(action.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(item.isBlocked)
                    }

                    Spacer(minLength: AppTheme.Spacing.s)

                    SizeText(bytes: item.sizeBytes, isUpperBound: item.sizeIsUpperBound, emphasized: isSelected)
                }

                Text(item.actions.count > 1 ? model.action(for: item).explanation : item.explanation)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppTheme.Spacing.xs) {
                    RegenerationTag(regeneration: model.action(for: item).regeneration)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.top, 1)

                if let note = item.note, !item.isBlocked {
                    InlineNote(text: note, symbolName: "arrow.down.circle")
                }
                if let warning = item.warning, !item.isBlocked {
                    InlineNote(text: warning, symbolName: "exclamationmark.triangle", tone: .warning)
                }
                if let blocked = item.blockedReason {
                    InlineNote(text: blocked, symbolName: item.needsFullDiskAccess ? "lock" : "pause.circle")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !item.isBlocked else { return }
                model.setSelected(item, !isSelected)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 10)
        .opacity(item.isBlocked ? 0.6 : 1)
        .hoverHighlight()
        .contextMenu {
            Button("Always Skip “\(item.title)”") { model.alwaysSkip(item) }
            Text("You can undo this in Settings › Never Clean.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Always Skip") { model.alwaysSkip(item) }
    }
}

// MARK: - Confirmation

/// Says exactly what will happen, grouped by whether it comes back, before anything runs.
struct ConfirmCleanSheet: View {
    let model: CleanUpViewModel
    @Environment(\.dismiss) private var dismiss

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
            }
            .frame(maxHeight: 380)

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
        var parts = ["\(model.selectionHasUpperBound ? "Up to " : "About ")\(ByteSize.string(model.selectedFreeingBytes)) will be freed."]
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
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.item.actions.count > 1 ? "\(selection.action.title) \(selection.item.title)" : selection.item.title)
                    .font(AppTheme.Typography.body)
                if case .command(let command) = selection.action.operation {
                    Text(command.displayString)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: AppTheme.Spacing.s)
            SizeText(bytes: selection.item.sizeBytes, isUpperBound: selection.item.sizeIsUpperBound)
        }
        .padding(.horizontal, AppTheme.Spacing.s)
        .padding(.vertical, 7)
    }
}
