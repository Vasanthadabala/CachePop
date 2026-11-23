import QuickLook
import SwiftUI

struct LargeFilesView: View {
    @Bindable var model: LargeFilesViewModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .start:
                FeatureIntroScreen(
                    points: [
                        FeatureIntroPoint(symbolName: "arrow.up.doc", title: "Large files", subtitle: "Anything over \(model.thresholdDescription). Change it in Settings."),
                        FeatureIntroPoint(symbolName: "doc.on.doc", title: "Duplicates", subtitle: "Identical contents, checked byte for byte."),
                        FeatureIntroPoint(symbolName: "chevron.left.forwardslash.chevron.right", title: "Projects are skipped", subtitle: "Source folders and build output are left alone."),
                        FeatureIntroPoint(symbolName: "photo.on.rectangle", title: "Libraries stay closed", subtitle: "Photos and Music libraries aren't opened.")
                    ],
                    pointsTitle: "What it looks for"
                ) {
                    FeatureIntroHeader(
                        section: .largeFiles,
                        title: "Large files and duplicates",
                        detail: "Find files over \(model.thresholdDescription) and identical copies. Review them before moving them to the Trash."
                    ) {
                        FlowLayout(spacing: AppTheme.Spacing.m, lineSpacing: AppTheme.Spacing.s) {
                            Button(action: model.scan) {
                                Label("Find Large Files", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(CapsuleButtonStyle())
                            .keyboardShortcut(.defaultAction)

                            ScopePicker(model: model)
                        }
                    }
                }
            case .scanning:
                ProgressPanel(
                    title: "Looking for large and duplicate files…",
                    detail: model.currentPath.isEmpty ? nil : abbreviate(model.currentPath, home: model.home),
                    onCancel: model.cancelScan
                )
            case .results:
                LargeFilesResultsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppTheme.Motion.quick, value: model.phase)
    }
}

private struct ScopePicker: View {
    let model: LargeFilesViewModel

    var body: some View {
        Menu {
            Button(model.defaultScopeTitle, action: model.useHomeFolders)
            Button("Choose Folder…", action: model.chooseFolder)
        } label: {
            Label(model.chosenFolder?.lastPathComponent ?? model.defaultScopeTitle, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 200, alignment: .leading)
        .accessibilityLabel("Scan location, \(model.scopeName)")
        .help(model.scopeName)
    }
}

// MARK: - Results

private struct LargeFilesResultsView: View {
    @Bindable var model: LargeFilesViewModel

    private var total: Int64 { model.result.reviewBytes }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    summary

                    if let message = model.message {
                        messageBanner(message)
                    }
                    if model.result.unreadableCount > 0 {
                        NoticeBanner(text: "Some folders or files couldn't be read. Check their locations and permissions, then scan again.", tone: .warning)
                    }
                    if model.result.wasLimited {
                        NoticeBanner(text: "This scan reached its file limit. Choose a smaller folder to check the remaining files.", tone: .warning)
                    }

                    HStack(spacing: AppTheme.Spacing.xs) {
                        Picker("Show", selection: $model.tab) {
                            Text("Large files  \(model.result.largeFiles.count)").tag(LargeFilesViewModel.Tab.large)
                            Text("Duplicates  \(model.result.duplicates.count)").tag(LargeFilesViewModel.Tab.duplicates)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        Spacer(minLength: AppTheme.Spacing.s)

                        if model.tab == .large && !model.result.largeFiles.isEmpty {
                            filterMenus
                        }
                    }
                    .padding(.top, AppTheme.Spacing.xxs)

                    switch model.tab {
                    case .large: largeList
                    case .duplicates: duplicateList
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, AppTheme.Spacing.m)
                .clearsActionBar()
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.space) {
                model.togglePreview()
                return .handled
            }
            .quickLookPreview($model.previewURL, in: model.previewableURLs)

            FloatingActionBar(
                summary: model.selectedFiles.isEmpty
                    ? "Nothing selected"
                    : "\(model.selectedFiles.count) \(model.selectedFiles.count == 1 ? "file" : "files") · \(ByteSize.string(model.selectedBytes))",
                detail: "Moved to the Trash. Nothing is deleted."
            ) {
                Button("Move to Trash…") { model.isConfirming = true }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedFiles.isEmpty || model.isMoving)
            }
        }
        .confirmationDialog(
            "Move \(model.selectedFiles.count) \(model.selectedFiles.count == 1 ? "file" : "files") to the Trash?",
            isPresented: $model.isConfirming
        ) {
            Button("Move to Trash", action: model.moveSelectedToTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(ByteSize.string(model.selectedBytes)) will be freed once you empty the Trash. Until then you can put them back.")
        }
    }

    private func messageBanner(_ message: String) -> NoticeBanner {
        let putBack: (() -> Void)? = model.canPutBack ? { model.putBack() } : nil
        return NoticeBanner(
            text: message,
            tone: .success,
            actionTitle: model.canPutBack ? "Put Back" : nil,
            action: putBack,
            onDismiss: { model.message = nil }
        )
    }

    private var summary: some View {
        let found = ByteSize.parts(total)
        return TapeHeader(
            caption: "Found",
            value: found.number,
            unit: found.unit,
            detail: "in \(model.result.largeFiles.count) large \(model.result.largeFiles.count == 1 ? "file" : "files") and \(model.result.duplicates.count) \(model.result.duplicates.count == 1 ? "set" : "sets") of copies · \(model.scopeName)"
        ) {
            Button {
                model.startOver()
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
            }
        } visual: {
            if total > 0 {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                    BreakdownBar(segments: segments, showsUnselectedColors: true)
                    FlowLayout(spacing: AppTheme.Spacing.m, lineSpacing: AppTheme.Spacing.xs) {
                        ForEach(segments.filter { $0.total > 0 }) { LegendItem(segment: $0) }
                    }
                }
            }
        }
    }

    /// Large files and extra copies, coloured where ticked.
    private var segments: [BreakdownSegment] {
        let selected = Set(model.selectedIDs)
        let largeTotal = model.result.otherLargeFiles.reduce(Int64(0)) { $0 + $1.size }
        let largeSelected = model.result.otherLargeFiles.filter { selected.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
        let copiesSelected = model.result.extraCopies.filter { selected.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
        return [
            BreakdownSegment(id: "large", title: "Large files", color: AppTheme.Palette.blue.solid,
                             total: largeTotal, selected: largeSelected),
            BreakdownSegment(id: "copies", title: "Extra copies", color: AppTheme.Palette.blue.solid,
                             total: model.result.duplicateExtraBytes, selected: min(copiesSelected, model.result.duplicateExtraBytes))
        ]
    }

    @ViewBuilder
    private var largeList: some View {
        if model.result.largeFiles.isEmpty {
            EmptyStateView(symbolName: "doc", title: "No large files", message: "Nothing over \(model.thresholdDescription) was found here.")
                .frame(height: 170)
                .card()
        } else {
            if model.filteredLargeFiles.isEmpty {
                EmptyStateView(symbolName: "line.3.horizontal.decrease.circle", title: "No matches", message: "No large files match these filters.") {
                    Button("Show All") {
                        model.kindFilter = nil
                        model.ageFilter = .any
                    }
                }
                .frame(height: 170)
                .card()
            } else {
                // Lazy: every tick redraws this list, and each row loads a Finder icon.
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.filteredLargeFiles.enumerated()), id: \.element.id) { index, file in
                        if index > 0 { RowDivider(leadingInset: 72) }
                        FileRow(file: file, home: model.home, isSelected: model.selectedIDs.contains(file.id),
                                isCurrent: model.currentFileID == file.id, onPreview: { model.preview(file) }) {
                            model.toggle(file)
                        }
                    }
                }
                .card()
            }
        }
    }

    /// Compact filter buttons: kind and age.
    private var filterMenus: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Menu {
                Picker("Kind", selection: $model.kindFilter) {
                    Text("All kinds").tag(FileKind?.none)
                    Divider()
                    ForEach(FileKind.allCases) { kind in
                        Text("\(kind.title)  \(model.count(of: kind))").tag(FileKind?.some(kind))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(model.kindFilter?.title ?? "All kinds", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            .help("Show only one kind of file")

            Menu {
                Picker("Age", selection: $model.ageFilter) {
                    ForEach(FileAge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(model.ageFilter == .any ? "Any date" : model.ageFilter.title, systemImage: "calendar")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            .help("Show only files you haven't changed in a while")
        }
    }

    @ViewBuilder
    private var duplicateList: some View {
        if model.result.duplicates.isEmpty {
            EmptyStateView(symbolName: "doc.on.doc", title: "No duplicates", message: "No identical files over 1 MB were found here.")
                .frame(height: 170)
                .card()
        } else {
            HStack {
                InlineNote(text: "The newest copy of each file is kept unless you tick it.")
                Spacer()
                Button("Select Extra Copies", action: model.selectExtraCopies)
            }

            // Lazy: a home folder can hold thousands of sets, all redrawn on every tick.
            LazyVStack(spacing: AppTheme.Spacing.m) {
                ForEach(model.result.duplicates) { set in
                    VStack(spacing: 0) {
                        CardHeader(
                            set.files.first?.name ?? "File",
                            symbolName: "doc.on.doc"
                        ) {
                            HStack(spacing: AppTheme.Spacing.s) {
                                Pill(text: "\(set.files.count) copies")
                                SizeText(bytes: set.extraBytes, emphasized: true)
                            }
                        }
                        RowDivider(leadingInset: 0)
                        ForEach(Array(set.files.enumerated()), id: \.element.id) { index, file in
                            if index > 0 { RowDivider(leadingInset: 72) }
                            FileRow(file: file, home: model.home, isSelected: model.selectedIDs.contains(file.id), tag: index == 0 ? "Newest" : nil,
                                    isCurrent: model.currentFileID == file.id, onPreview: { model.preview(file) }) {
                                model.toggle(file)
                            }
                        }
                        if model.allCopiesSelected(set) {
                            RowDivider(leadingInset: 0)
                            InlineNote(text: "Every copy is ticked, so none would be left.", symbolName: "exclamationmark.triangle", tone: .warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.Spacing.m)
                                .padding(.vertical, 7)
                        }
                    }
                    .card()
                }
            }
        }
    }
}

private struct FileRow: View {
    let file: FoundFile
    let home: URL
    let isSelected: Bool
    var tag: String?
    var isCurrent = false
    var onPreview: () -> Void = {}
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            SelectionBox(state: isSelected ? .on : .off, action: onToggle)

            FinderIcon(path: file.url.path, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(file.name)
                        .font(AppTheme.Typography.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(abbreviate(file.url.path, home: home))
                    if let tag {
                        Pill(text: tag)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            Spacer(minLength: AppTheme.Spacing.s)

            SizeText(bytes: file.size, emphasized: isSelected)

            Button(action: onPreview) {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick Look (Space)")

            RevealButton(path: file.url.path)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
        .background(isCurrent ? AppTheme.Colors.hover : .clear)
        .hoverHighlight()
    }
}

/// A quiet "Show in Finder" button for list rows.
struct RevealButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.revealInFinder(path)
        } label: {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
    }
}

/// "/Users/me/Movies" → "~/Movies". Both sides are canonicalised, so `/var` and
/// `/private/var` homes (fixtures, demo mode) abbreviate too.
func abbreviate(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
    let homePath = PathSafety.canonicalPath(home) ?? home.path
    let fullPath = PathSafety.canonicalPath(URL(fileURLWithPath: path)) ?? path
    if fullPath == homePath { return "~" }
    return fullPath.hasPrefix(homePath + "/") ? "~" + fullPath.dropFirst(homePath.count) : path
}
