import SwiftUI

struct AppsView: View {
    @Bindable var model: AppsViewModel

    var body: some View {
        Group {
            if model.isScanning && !model.hasScanned {
                ProgressPanel(title: "Measuring your apps…", detail: "/Applications and ~/Applications")
            } else if model.hasScanned && model.applications.isEmpty {
                EmptyStateView(symbolName: "square.grid.2x2", title: "No apps found", message: "CachePop couldn't read your Applications folder.") {
                    Button("Scan Again", action: model.scan).secondaryAction()
                }
            } else {
                HStack(spacing: 0) {
                    AppListPane(model: model)
                        .frame(width: 280)
                    Rectangle()
                        .fill(AppTheme.Colors.separator)
                        .frame(width: 1)
                    AppDetailPane(model: model)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task { model.scanIfNeeded() }
    }
}

// MARK: - List

private struct AppListPane: View {
    @Bindable var model: AppsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // The top bar names the section and counts the apps; the list starts with its filters.
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                HStack {
                    Picker("Filter", selection: $model.filter) {
                        ForEach(AppFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Menu {
                        Picker("Sort By", selection: $model.sortOrder) {
                            ForEach(AppSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort by \(model.sortOrder.title.lowercased())")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.top, AppTheme.Spacing.s)
            .padding(.bottom, AppTheme.Spacing.xs)

            List(model.filteredApplications, selection: $model.selectedAppID) { app in
                AppRow(app: app)
                    .tag(app.id)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct AppRow: View {
    let app: ApplicationDetails

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            // App icons carry their own margins, so they sit a step above the row-icon size.
            AppIcon(app: app, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(AppTheme.Typography.body.weight(.medium))
                    .lineLimit(1)
                Text(app.isUnused ? "Not opened for \(app.lastUsedText.replacingOccurrences(of: " ago", with: ""))" : "Version \(app.version)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.xs)
            // App plus its Library files once measured; the bundle alone until then. Apps on
            // the sealed system volume (Safari) measure 0, so they say what they are instead.
            Text(app.isProtected && app.totalSizeBytes == 0 ? "Part of macOS" : app.formattedTotalSize)
                .contentTransition(.numericText())
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.vertical, 3)
    }
}

private struct AppIcon: View {
    let app: ApplicationDetails
    let size: CGFloat

    var body: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            FinderIcon(path: app.path, size: size)
        }
    }
}

// MARK: - Detail

private struct AppDetailPane: View {
    @Bindable var model: AppsViewModel

    var body: some View {
        if let app = model.selectedApp {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                        if let result = model.lastUninstallResult {
                            NoticeBanner(
                                text: "Moved \(result.app.name) and \(max(result.filesRemoved - 1, 0)) leftover \(result.filesRemoved - 1 == 1 ? "item" : "items") (\(result.formattedBytesFreed)) to the Trash.",
                                tone: .success,
                                onDismiss: { model.lastUninstallResult = nil }
                            )
                        }
                        if let error = model.errorMessage {
                            NoticeBanner(text: error, tone: .warning, onDismiss: { model.errorMessage = nil })
                        }

                        hero(app)

                        if app.isProtected {
                            NoticeBanner(text: "This app is part of macOS or is CachePop itself, so it can't be removed.")
                        }

                        leftovers(app)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.top, AppTheme.Spacing.m)
                    .clearsActionBar()
                }

                FloatingActionBar(
                    summary: app.isProtected ? "Can't be removed" : "Remove \(app.name) · \(ByteSize.string(model.pendingReclaimBytes))",
                    detail: app.isProtected ? nil : "The app and ticked files go to the Trash."
                ) {
                    Button("Uninstall…", action: model.requestUninstall)
                        .primaryAction()
                        .disabled(app.isProtected || model.isUninstalling)
                }
            }
            .confirmationDialog("Uninstall \(app.name)?", isPresented: $model.isConfirming) {
                Button("Move to Trash", role: .destructive, action: model.confirmUninstall)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage(app))
            }
            .overlay {
                if model.isUninstalling {
                    ProgressPanel(title: "Uninstalling \(app.name)…")
                        .background(.regularMaterial)
                }
            }
        } else {
            EmptyStateView(symbolName: "square.grid.2x2", title: "Select an app", message: "See its size, when you last opened it, and the files it keeps in your Library.")
        }
    }

    /// The selected app's Library size: from its loaded file list, else the background measurement.
    private func libraryBytes(_ app: ApplicationDetails) -> Int64? {
        if !model.isLoadingRelatedFiles, model.selectedAppID == app.id, !model.relatedFiles.isEmpty {
            return model.relatedBytes
        }
        return app.librarySizeBytes
    }

    private func totalBytes(_ app: ApplicationDetails) -> Int64 {
        app.sizeBytes + (libraryBytes(app) ?? 0)
    }

    private func hero(_ app: ApplicationDetails) -> some View {
        let total = totalBytes(app)
        let parts = ByteSize.parts(total)
        let largest = max(model.applications.map(\.totalSizeBytes).max() ?? total, total, 1)
        let appEnd = Double(app.sizeBytes) / Double(largest)
        let totalEnd = Double(total) / Double(largest)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppIcon(app: app, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text("Version \(app.version) · Opened \(app.lastUsedText.lowercased())")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: AppTheme.Spacing.s)
                RevealButton(path: app.path)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.number)
                    .font(.system(size: 44, weight: .light))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(libraryBytes(app) == nil ? "\(parts.unit) · measuring Library…" : "\(parts.unit) in total")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.top, 12)

            TapeView(tape: Tape(
                segments: [
                    Tape.Segment(from: 0, to: appEnd, color: AppTheme.Colors.accent),
                    Tape.Segment(from: appEnd, to: totalEnd, color: AppTheme.Colors.accent, striped: true)
                ],
                leading: app.isProtected && app.sizeBytes == 0 ? "App: part of macOS" : "App \(app.formattedSize)",
                center: libraryBytes(app).map { "Library \(ByteSize.string($0))" },
                trailing: "Largest app \(ByteSize.string(largest))"
            ))
            .id(app.id)
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func leftovers(_ app: ApplicationDetails) -> some View {
        VStack(spacing: 0) {
            CardHeader(
                "Files in your Library",
                subtitle: leftoverSubtitle,
                symbolName: "folder"
            ) {
                if !model.relatedFiles.isEmpty && !app.isProtected {
                    Button(model.selectedRelatedFileIDs.count == model.relatedFiles.count ? "Deselect All" : "Select All",
                           action: model.toggleAllRelatedFiles)
                        .buttonStyle(.link)
                        .font(AppTheme.Typography.callout)
                }
            }
            RowDivider(leadingInset: 0)

            if model.selectedAppHasAnotherCopy && !model.relatedFiles.isEmpty && !app.isProtected {
                InlineNote(text: "Another copy of this app is installed and uses these files, so they start unticked.",
                           symbolName: "exclamationmark.triangle", tone: .warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, AppTheme.Spacing.s)
            }

            if model.isLoadingRelatedFiles {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Looking for settings, caches and support files…")
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.m)
            } else if model.relatedFiles.isEmpty {
                Text("No settings, caches or support files were found for this app.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.m)
            } else {
                ForEach(Array(model.relatedFiles.enumerated()), id: \.element.id) { index, file in
                    if index > 0 { RowDivider(leadingInset: 36) }
                    LeftoverRow(
                        file: file,
                        isSelected: model.selectedRelatedFileIDs.contains(file.id),
                        isDisabled: app.isProtected
                    ) { model.toggleRelatedFile(file) }
                }
            }
        }
        .card()
    }

    private var leftoverSubtitle: String {
        if model.isLoadingRelatedFiles { return "Searching…" }
        if model.relatedFiles.isEmpty { return "Nothing left behind" }
        return "Settings and data the app keeps. Keep them if you might reinstall."
    }

    private func confirmationMessage(_ app: ApplicationDetails) -> String {
        var text = "\(app.name) and \(model.selectedRelatedFiles.count) \(model.selectedRelatedFiles.count == 1 ? "file" : "files") from your Library (\(ByteSize.string(model.pendingReclaimBytes))) will be moved to the Trash."
        if app.isRunning { text += " The app will be quit first." }
        return text
    }
}

private struct LeftoverRow: View {
    let file: ApplicationRelatedFile
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            SelectionBox(state: isSelected ? .on : .off, isDisabled: isDisabled, action: onToggle)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.category)
                    .font(AppTheme.Typography.headline)
                Text(abbreviate(file.path))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppTheme.Spacing.s)
            if file.isReadable {
                SizeText(bytes: file.sizeBytes, emphasized: isSelected)
            } else {
                Text("Can't measure")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .help("macOS keeps this folder private. Give CachePop Full Disk Access to measure and remove it.")
            }
            RevealButton(path: file.path)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
        .hoverHighlight()
    }
}
