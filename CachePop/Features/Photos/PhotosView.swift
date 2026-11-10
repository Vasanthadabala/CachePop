import SwiftUI

struct PhotosView: View {
    @Bindable var model: PhotosViewModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .start:
                FeatureIntroScreen(
                    points: [
                        FeatureIntroPoint(symbolName: "square.on.square", title: "Similar shots", subtitle: "Retakes and bursts of the same moment. The best one is kept."),
                        FeatureIntroPoint(symbolName: "camera.aperture", title: "Blurry", subtitle: "Shake or missed focus, with nothing sharp in the frame."),
                        FeatureIntroPoint(symbolName: "moon", title: "Too dark", subtitle: "Shots where almost nothing can be seen."),
                        FeatureIntroPoint(symbolName: "sun.max", title: "Overexposed", subtitle: "Washed out, with most of the picture white."),
                        FeatureIntroPoint(symbolName: "heart", title: "Favourites are safe", subtitle: "Photos you've marked as favourites are never suggested.")
                    ],
                    pointsTitle: "What it looks for"
                ) {
                    TapeHeader(
                        caption: "Photo check",
                        value: "4",
                        unit: "things it looks for",
                        detail: "Nothing is removed until you choose. Files go to the Trash, and photos in your library go to Recently Deleted in Photos for 30 days."
                    ) {
                        HStack(spacing: AppTheme.Spacing.m) {
                            Button(action: model.scan) {
                                Label("Check Photos", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(CapsuleButtonStyle())
                            .keyboardShortcut(.defaultAction)

                            ScopeMenu(model: model)
                        }
                    }
                }
            case .scanning:
                ProgressPanel(
                    title: "Looking at your photos…",
                    detail: model.total > 0 ? "\(model.measured.formatted()) of \(model.total.formatted()) photos" : "Finding photos…",
                    progress: model.progress,
                    onCancel: model.cancelScan
                )
            case .results:
                PhotosResultsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppTheme.Motion.quick, value: model.phase)
    }
}

private struct ScopeMenu: View {
    @Bindable var model: PhotosViewModel

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: model.scope.includesLibrary ? "photo.on.rectangle" : "folder")
            Text(model.scope.title)
                .lineLimit(1)
            if model.scopes.count > 1 {
                Menu("Change") {
                    Picker("Look in", selection: $model.scope) {
                        ForEach(model.scopes) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .font(AppTheme.Typography.callout)
        .foregroundStyle(AppTheme.Colors.textSecondary)
    }
}

// MARK: - Results

private struct PhotosResultsView: View {
    @Bindable var model: PhotosViewModel

    private static let columns = [GridItem(.adaptive(minimum: PhotoTile.side, maximum: PhotoTile.side), spacing: 12, alignment: .top)]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    summary

                    if model.libraryAccessDenied {
                        NoticeBanner(
                            text: "Photos access is off, so only your folders were checked.",
                            tone: .warning,
                            actionTitle: "Open Settings",
                            action: model.openPhotosSettings
                        )
                    }

                    if let message = model.message {
                        NoticeBanner(
                            text: message,
                            tone: .success,
                            actionTitle: model.canPutBack ? "Put Back" : nil,
                            action: model.canPutBack ? { model.putBack() } : nil,
                            onDismiss: { model.message = nil }
                        )
                    }

                    HStack(spacing: AppTheme.Spacing.xs) {
                        Picker("Show", selection: $model.tab) {
                            ForEach(PhotosViewModel.Tab.allCases) { tab in
                                Text("\(tab.title)  \(model.count(in: tab))").tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        Spacer(minLength: AppTheme.Spacing.s)

                        tabActions
                    }
                    .padding(.top, AppTheme.Spacing.xxs)

                    if let issue = model.tab.issue {
                        issueGrid(issue)
                    } else {
                        similarList
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, AppTheme.Spacing.m)
                .clearsActionBar()
            }

            FloatingActionBar(
                summary: model.selectedPhotos.isEmpty
                    ? "Nothing selected"
                    : "\(model.selectedPhotos.count) \(model.selectedPhotos.count == 1 ? "photo" : "photos") selected",
                detail: actionDetail
            ) {
                Button("Remove…") { model.isConfirming = true }
                    .primaryAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedPhotos.isEmpty || model.isRemoving)
            }
        }
        .confirmationDialog(
            "Remove \(model.selectedPhotos.count) \(model.selectedPhotos.count == 1 ? "photo" : "photos")?",
            isPresented: $model.isConfirming
        ) {
            Button("Remove", action: model.removeSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var actionDetail: String {
        switch (model.selectedFileCount > 0, model.selectedLibraryCount > 0) {
        case (true, true):  "Files go to the Trash. Library photos go to Recently Deleted."
        case (true, false): "Moved to the Trash, so you can put them back."
        case (false, true): "Moved to Recently Deleted in Photos for 30 days."
        case (false, false): "Tick the photos you don't want."
        }
    }

    private var confirmMessage: String {
        var parts: [String] = []
        if model.selectedFileCount > 0 {
            parts.append("\(model.selectedFileCount) \(model.selectedFileCount == 1 ? "file goes" : "files go") to the Trash (\(ByteSize.string(model.selectedBytes))). Until you empty it, you can put them back.")
        }
        if model.selectedLibraryCount > 0 {
            parts.append("\(model.selectedLibraryCount) library \(model.selectedLibraryCount == 1 ? "photo goes" : "photos go") to Recently Deleted in Photos, which asks you to confirm. You can recover them there for 30 days.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var tabActions: some View {
        if model.tab == .similar, !model.result.similar.isEmpty {
            Button("Select All But Best", action: model.selectAllButBest)
        } else if let issue = model.tab.issue, !model.result.photos(with: issue).isEmpty {
            Button("Select All") { model.selectAll(issue) }
        }
        if !model.selectedIDs.isEmpty {
            Button("Deselect All", action: model.deselectAll)
        }
    }

    private var summary: some View {
        let result = model.result
        let parts = [
            "\(result.similar.count) \(result.similar.count == 1 ? "group" : "groups") of similar shots",
            "\(result.photos(with: .blurry).count) blurry",
            "\(result.photos(with: .dark).count) too dark",
            "\(result.photos(with: .overexposed).count) overexposed"
        ]
        return TapeHeader(
            caption: "To review",
            value: result.reviewCount.formatted(),
            unit: result.reviewCount == 1 ? "photo" : "photos",
            detail: parts.joined(separator: " · ") + " · \(result.analyzedCount.formatted()) checked in \(model.scope.title.lowercased())"
        ) {
            Button {
                model.startOver()
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
            }
        } visual: {
            EmptyView()
        }
    }

    // MARK: Similar

    @ViewBuilder
    private var similarList: some View {
        if model.result.similar.isEmpty {
            EmptyStateView(symbolName: "square.on.square", title: "No similar shots", message: "No retakes of the same moment were found.")
                .frame(height: 170)
                .card()
        } else {
            InlineNote(text: "The best shot of each group is marked Keep and stays unless you tick it.")
            LazyVStack(spacing: AppTheme.Spacing.m) {
                ForEach(model.result.similar) { group in
                    VStack(spacing: 0) {
                        CardHeader(
                            "\(group.photos.count) similar shots",
                            subtitle: group.photos[0].date?.formatted(date: .abbreviated, time: .shortened),
                            symbolName: "square.on.square",
                            hue: AppTheme.Palette.violet
                        )
                        RowDivider(leadingInset: 0)
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                            ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, photo in
                                PhotoTile(photo: photo, isSelected: model.selectedIDs.contains(photo.id),
                                          tag: index == 0 ? "Keep" : nil) { model.toggle(photo) }
                            }
                        }
                        .padding(AppTheme.Spacing.m)
                        if model.allSelected(group) {
                            RowDivider(leadingInset: 0)
                            InlineNote(text: "Every shot is ticked, so none of this moment would be left.", symbolName: "exclamationmark.triangle", tone: .warning)
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

    // MARK: Issues

    @ViewBuilder
    private func issueGrid(_ issue: PhotoIssue) -> some View {
        let photos = model.result.photos(with: issue)
        if photos.isEmpty {
            EmptyStateView(symbolName: "checkmark.circle", title: "None \(issue.title.lowercased())", message: "No photos look \(issue.title.lowercased()).")
                .frame(height: 170)
                .card()
        } else {
            InlineNote(text: note(for: issue))
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                ForEach(photos) { photo in
                    PhotoTile(photo: photo, isSelected: model.selectedIDs.contains(photo.id)) { model.toggle(photo) }
                }
            }
            .padding(AppTheme.Spacing.m)
            .card()
        }
    }

    private func note(for issue: PhotoIssue) -> String {
        switch issue {
        case .blurry:      "Nothing in these is sharp. Some may be blurred on purpose, so look before you tick."
        case .dark:        "Almost nothing can be seen in these. Night shots can land here too."
        case .overexposed: "Most of the picture is white. Snow and bright skies can land here too."
        }
    }
}

// MARK: - Tile

private struct PhotoTile: View {
    static let side: CGFloat = 132

    let photo: AnalyzedPhoto
    let isSelected: Bool
    var tag: String?
    let onToggle: () -> Void

    @State private var thumbnail: PhotoThumbnails.Box?

    private var caption: String {
        [photo.date?.formatted(date: .abbreviated, time: .omitted), photo.bytes.map(ByteSize.string)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(AppTheme.Colors.tile)
                    .overlay {
                        if let thumbnail {
                            Image(decorative: thumbnail.image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .strokeBorder(isSelected ? AppTheme.Colors.accent : .clear, lineWidth: 2.5)
                    }

                SelectionBox(state: isSelected ? .on : .off, action: onToggle)
                    .padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if let tag { Pill(text: tag, symbolName: "checkmark", tone: .success) }
                    if photo.isFavorite { Pill(text: "Favourite", symbolName: "heart.fill") }
                }
                .padding(6)
            }

            Text(caption.isEmpty ? photo.name : caption)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
            Text(photo.isInLibrary ? "Photos library" : abbreviate(photo.fileURL?.deletingLastPathComponent().path ?? ""))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: Self.side)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .contextMenu {
            if let url = photo.fileURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Open") { NSWorkspace.shared.open(url) }
            }
        }
        .task(id: photo.id) {
            thumbnail = await PhotoThumbnails.load(photo, side: Int(Self.side * 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(photo.name)\(tag.map { ", \($0)" } ?? "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
    }
}
