import SwiftUI

/// What's taking up space: the whole disk at a glance, then any folder, one level at a time.
/// Read-only — it points to the section that can help instead of deleting anything itself.
struct DiskUsageView: View {
    let model: DiskUsageViewModel
    let disk: DiskInfo
    let onOpenSection: (AppSection) -> Void

    var body: some View {
        ZStack {
            switch model.phase {
            case .start:
                FeatureIntroScreen(
                    points: [
                        FeatureIntroPoint(symbolName: "chart.bar.xaxis", title: "Whole disk", subtitle: "Apps, your files, and macOS at a glance."),
                        FeatureIntroPoint(symbolName: "folder", title: "Folder by folder", subtitle: "Open any folder to see its biggest items."),
                        FeatureIntroPoint(symbolName: "arrow.turn.down.right", title: "Where to go next", subtitle: "Links to the section that can free that space."),
                        FeatureIntroPoint(symbolName: "lock", title: "Read-only", subtitle: "Measuring never moves or deletes anything.")
                    ],
                    pointsTitle: "How it works"
                ) {
                    let used = ByteSize.parts(disk.usedBytes)
                    FeatureIntroHeader(
                        section: .diskUsage,
                        caption: disk.volumeName,
                        title: disk.totalBytes > 0 ? used.number : "—",
                        unit: disk.totalBytes > 0 ? "\(used.unit) used" : nil,
                        detail: disk.totalBytes > 0
                            ? "Explore what’s using your \(ByteSize.string(disk.totalBytes)) of storage, folder by folder."
                            : "Explore disk usage, folder by folder.",
                        disk: disk
                    ) {
                        Button(action: model.start) {
                            Label("Measure My Disk", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
            case .measuring, .ready:
                DiskUsageBrowser(model: model, disk: disk, onOpenSection: onOpenSection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppTheme.Motion.quick, value: model.phase)
    }
}

private struct DiskUsageBrowser: View {
    let model: DiskUsageViewModel
    let disk: DiskInfo
    let onOpenSection: (AppSection) -> Void

    var body: some View {
        // Sorted once per redraw: each of these used to sort the whole listing again.
        let entries = model.currentEntries
        let rows = entries.filter { ($0.bytes ?? .max) >= DiskUsagePolicy.minimumRowBytes }
        let smallEntries = entries.filter { ($0.bytes ?? .max) < DiskUsagePolicy.minimumRowBytes }
        let largestBytes = entries.compactMap(\.bytes).max() ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                if model.path.isEmpty {
                    DiskOverviewCard(model: model, disk: disk)
                } else {
                    FolderHeaderCard(model: model, totalBytes: entries.compactMap(\.bytes).reduce(0, +))
                }

                if model.hasUnreadableParts && !PermissionsManager.shared.hasFullDiskAccess {
                    PermissionPromptView(reason: "Some folders are private to macOS, so their sizes may show lower than they are.", showsDetails: false)
                }

                // Lazy: a folder can hold thousands of items, and each row loads a Finder icon.
                LazyVStack(spacing: 0) {
                    HStack(spacing: AppTheme.Spacing.s) {
                        Image(systemName: "list.bullet.indent")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(model.path.isEmpty ? "Largest folders" : "Inside \(model.path.last?.lastPathComponent ?? "")")
                            .font(AppTheme.Typography.title2)
                        Spacer(minLength: AppTheme.Spacing.s)
                        if !model.isMeasuringCurrent {
                            Text("\(entries.count) items · largest first")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, AppTheme.Spacing.s)
                    RowDivider(leadingInset: 0)

                    // Not while it's still being listed.
                    if entries.isEmpty && !model.isMeasuringCurrent {
                        Text("This folder is empty, or CachePop can't look inside it.")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.Spacing.m)
                    }

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider(leadingInset: 44) }
                        UsageRow(
                            entry: entry,
                            share: largestBytes > 0 ? Double(entry.bytes ?? 0) / Double(largestBytes) : 0,
                            caption: model.path.isEmpty ? abbreviate(entry.url.path, home: model.home) : nil,
                            hint: hint(for: entry.url),
                            onOpen: { model.open(entry) },
                            onOpenSection: onOpenSection
                        )
                    }

                    if !smallEntries.isEmpty && !model.isMeasuringCurrent {
                        RowDivider(leadingInset: 44)
                        HStack(spacing: AppTheme.Spacing.s) {
                            IconTile(symbolName: "ellipsis", size: AppTheme.Layout.rowIcon)
                            Text("\(smallEntries.count) smaller \(smallEntries.count == 1 ? "item" : "items")")
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            SizeText(bytes: smallEntries.compactMap(\.bytes).reduce(0, +))
                        }
                        .padding(.horizontal, AppTheme.Spacing.m)
                        .padding(.vertical, 7)
                    }
                }
                .card()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.m)
        }
    }

    /// Which section can do something about this folder.
    private func hint(for url: URL) -> (title: String, section: AppSection)? {
        if url == model.applications { return ("Applications", .apps) }
        let relative = abbreviate(url.path, home: model.home)
        guard relative.hasPrefix("~/") else { return nil }
        let path = String(relative.dropFirst(2))
        let cleanUp = ["Library/Caches", "Library/Developer", "Library/Logs", "Library/Android", ".npm", ".gradle",
                       ".cache", ".Trash", ".android", ".cocoapods", ".cargo", ".m2", ".pub-cache", ".bun",
                       "Library/Application Support/MobileSync", "Library/iTunes"]
        if cleanUp.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return ("Clean Up", .cleanUp) }
        let largeFiles = ["Downloads", "Movies", "Documents", "Desktop", "Music", "Pictures"]
        if largeFiles.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return ("Large Files", .largeFiles) }
        if path == "Library" { return ("Clean Up", .cleanUp) }
        return nil
    }
}

// MARK: - Overview

private struct DiskOverviewCard: View {
    let model: DiskUsageViewModel
    let disk: DiskInfo

    private var otherBytes: Int64 {
        max(disk.usedBytes - model.applicationsBytes - model.homeBytes, 0)
    }

    private var parts: [(title: String, bytes: Int64, color: Color)] {
        [
            ("Applications", model.applicationsBytes, AppTheme.Palette.blue.solid),
            ("Home folder", model.homeBytes, AppTheme.Palette.red.solid),
            ("macOS & other", otherBytes, AppTheme.Palette.orange.solid),
            ("Free", disk.availableBytes, AppTheme.Palette.green.solid)
        ]
    }

    var body: some View {
        let used = ByteSize.parts(disk.usedBytes)
        TapeHeader(
            caption: disk.volumeName,
            value: used.number,
            unit: "\(used.unit) used",
            detail: "of \(ByteSize.string(disk.totalBytes)) · \(ByteSize.string(disk.availableBytes)) free"
        ) {
            if model.isMeasuringCurrent {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    model.rescan()
                } label: {
                    Label("Measure Again", systemImage: "arrow.clockwise")
                }
            }
        } visual: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                GeometryReader { proxy in
                    let visible = parts.filter { $0.bytes > 0 }
                    let widths = BreakdownGeometry.widths(for: visible.map(\.bytes), availableWidth: proxy.size.width)
                    HStack(spacing: 3) {
                        ForEach(Array(visible.enumerated()), id: \.element.title) { index, part in
                            Capsule()
                                .fill(part.color)
                                .frame(width: widths[index])
                        }
                    }
                }
                .frame(height: 8)
                .animation(AppTheme.Motion.standard, value: model.homeBytes)

                FlowLayout(spacing: AppTheme.Spacing.m, lineSpacing: AppTheme.Spacing.xs) {
                    ForEach(parts, id: \.title) { part in
                        HStack(spacing: 6) {
                            Circle().fill(part.color).frame(width: 8, height: 8)
                            Text(part.title)
                                .font(AppTheme.Typography.callout)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(ByteSize.string(part.bytes))
                                .font(AppTheme.Typography.callout.weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }

            }
        }
    }
}

private struct FolderHeaderCard: View {
    let model: DiskUsageViewModel
    let totalBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(spacing: 4) {
                crumb("Disk") { model.goBack(to: nil) }
                ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    if index == model.path.count - 1 {
                        Text(url.lastPathComponent)
                            .font(AppTheme.Typography.callout.weight(.semibold))
                            .lineLimit(1)
                    } else {
                        crumb(url.lastPathComponent) { model.goBack(to: index) }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    TapeFigure(bytes: totalBytes)
                    Text(abbreviate(model.path.last?.path ?? "", home: model.home))
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    model.goBack(to: model.path.count >= 2 ? model.path.count - 2 : nil)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                if let folder = model.path.last {
                    Button {
                        NSWorkspace.shared.revealInFinder(folder.path)
                    } label: {
                        Label("Show in Finder", systemImage: "arrow.up.forward.square")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card()
    }

    private func crumb(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.accent)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct UsageRow: View {
    let entry: UsageEntry
    let share: Double
    let caption: String?
    let hint: (title: String, section: AppSection)?
    let onOpen: () -> Void
    let onOpenSection: (AppSection) -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            FinderIcon(path: entry.url.path, size: AppTheme.Layout.rowIcon)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(entry.name)
                        .font(AppTheme.Typography.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let caption {
                        Text(caption)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.Colors.track)
                        Capsule()
                            .fill(AppTheme.Palette.blue.solid)
                            .frame(width: entry.bytes == nil ? 0 : max(proxy.size.width * share, 3))
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: 260)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Spacer(minLength: AppTheme.Spacing.s)

            if let hint {
                Button {
                    onOpenSection(hint.section)
                } label: {
                    Label(hint.title, systemImage: "arrow.turn.down.right")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(HintPillStyle())
                .help("Open \(hint.title)")
            }

            if let bytes = entry.bytes {
                SizeText(bytes: bytes, emphasized: true)
            } else {
                ProgressView().controlSize(.small)
            }

            RevealButton(path: entry.url.path)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .opacity(entry.isDirectory ? 1 : 0)
                .frame(width: 12)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(entry.isDirectory ? .isButton : [])
        .accessibilityAction { onOpen() }
        .focusable(entry.isDirectory)
        .onKeyPress(.return) {
            guard entry.isDirectory else { return .ignored }
            onOpen()
            return .handled
        }
        .onKeyPress(.space) {
            guard entry.isDirectory else { return .ignored }
            onOpen()
            return .handled
        }
    }
}

/// "Go to the section that can free this" on a folder row: grey like the other row details,
/// accent while the pointer is over it, so a long list doesn't fill up with blue.
private struct HintPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HintPill(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct HintPill<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @State private var isHovered = false

        var body: some View {
            label
                .foregroundStyle(isHovered ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(isHovered ? AppTheme.Colors.accentSoft : AppTheme.Colors.tile))
                .opacity(isPressed ? 0.7 : 1)
                .contentShape(Capsule())
                .onHover { hovering in
                    withAnimation(AppTheme.Motion.quick) { isHovered = hovering }
                }
        }
    }
}
