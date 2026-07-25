import SwiftUI

// MARK: - App List

struct AppListPane: View {
    @Bindable var viewModel: AppManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.filteredApplications.count) apps")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)

                Spacer()

                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(AppTheme.Colors.border)

            if viewModel.filteredApplications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)

                    Text("No apps match this filter")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.filteredApplications) { app in
                            AppListRow(
                                app: app,
                                isSelected: viewModel.selectedAppID == app.id
                            ) {
                                viewModel.select(app)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }
}

struct AppListRow: View {
    let app: ApplicationDetails
    let isSelected: Bool
    let action: () -> Void

    private let accent = FeatureAccent.appManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 34, height: 34)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.tint)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "app.fill")
                                .foregroundStyle(accent.solid)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)

                        if app.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }

                    Text(app.isUnused ? "Unused · \(app.lastUsedText)" : app.lastUsedText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(app.isUnused ? FeatureAccent.boost.solid : AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(app.formattedSize)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.tint : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .rowHoverHighlight(cornerRadius: 10)
    }
}

// MARK: - Detail Pane

struct AppDetailPane: View {
    @Bindable var viewModel: AppManagerViewModel

    private let accent = FeatureAccent.appManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let app = viewModel.selectedApp {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(for: app)

                        Divider().overlay(AppTheme.Colors.border)

                        metaGrid(for: app)

                        Divider().overlay(AppTheme.Colors.border)

                        leftoverSection(for: app)
                    }
                    .padding(24)
                }

                Divider().overlay(AppTheme.Colors.border)

                footer(for: app)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(AppTheme.Colors.textTertiary)

                    Text("Select an app to inspect it")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    private func header(for app: ApplicationDetails) -> some View {
        HStack(spacing: 16) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 62, height: 62)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text("Version \(app.version)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 6) {
                    if app.isProtected {
                        AccentPillBadge(accent: .dashboard, text: "System app")
                    }
                    if app.isRunning {
                        AccentPillBadge(accent: .cleanup, text: "Running")
                    }
                    if app.isUnused {
                        AccentPillBadge(accent: .boost, text: "Unused")
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
    }

    private func metaGrid(for app: ApplicationDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailMetaLine(label: "Size", value: app.formattedSize)
            DetailMetaLine(label: "Last used", value: app.lastUsedText)
            DetailMetaLine(label: "Identifier", value: app.bundleIdentifier.isEmpty ? "Unknown" : app.bundleIdentifier)
            DetailMetaLine(label: "Location", value: app.path)
        }
    }

    private func leftoverSection(for app: ApplicationDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Leftover Files")

                Spacer()

                if !viewModel.relatedFiles.isEmpty {
                    Button {
                        viewModel.toggleAllRelatedFiles()
                    } label: {
                        Text(viewModel.selectedRelatedFileIDs.count == viewModel.relatedFiles.count ? "Deselect all" : "Select all")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(accent.solid)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isLoadingRelatedFiles {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text("Looking for support files…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.relatedFiles.isEmpty {
                Text("No leftover files found for this app.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.relatedFiles) { file in
                        LeftoverFileRow(
                            file: file,
                            isSelected: viewModel.selectedRelatedFileIDs.contains(file.id),
                            onToggle: { viewModel.toggleRelatedFile(file) },
                            onReveal: { viewModel.revealInFinder(file.path) }
                        )
                    }
                }
            }
        }
    }

    private func footer(for app: ApplicationDetails) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.isProtected ? "Protected by macOS" : "Will free \(viewModel.formattedPendingReclaim)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(app.isProtected
                     ? "System applications can't be removed."
                     : "App bundle + \(viewModel.selectedRelatedFiles.count) leftover item(s) → Trash")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Button("Reveal in Finder") {
                viewModel.revealInFinder(app.path)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .buttonStyle(.appInteractive)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.Colors.glassBg)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
            }

            Button("Uninstall") {
                viewModel.requestUninstall()
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .buttonStyle(.appInteractive)
            .padding(.horizontal, 22)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(app.isProtected ? AnyShapeStyle(AppTheme.Colors.textTertiary) : AnyShapeStyle(accent.gradient))
            }
            .disabled(app.isProtected)
            .opacity(app.isProtected ? 0.6 : 1)
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }
}

private struct DetailMetaLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .frame(width: 84, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}

struct LeftoverFileRow: View {
    let file: ApplicationRelatedFile
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    private let accent = FeatureAccent.appManager

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? accent.solid : AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.category)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }

            Spacer(minLength: 6)

            Text(file.formattedSize)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Button(action: onReveal) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.Colors.glassBg)
        }
    }
}

// MARK: - Confirmation / Progress / Result

struct UninstallConfirmationDialog: View {
    let app: ApplicationDetails
    let leftoverCount: Int
    let totalSize: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(FeatureAccent.clutter.tint)
                            .frame(width: 58, height: 58)

                        Image(systemName: "trash.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(FeatureAccent.clutter.solid)
                    }

                    VStack(spacing: 7) {
                        Text("Uninstall \(app.name)?")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("The app and \(leftoverCount) leftover item(s) will be moved to the Trash, freeing about \(totalSize). You can restore them from the Trash.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if app.isRunning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(FeatureAccent.boost.solid)

                            Text("\(app.name) is running and will be asked to quit first.")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(FeatureAccent.boost.tint)
                        }
                    }
                }
                .padding(28)

                Divider().overlay(AppTheme.Colors.border)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .buttonStyle(.appInteractive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppTheme.Colors.glassBg)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                                }
                        }

                    Button("Move to Trash", action: onConfirm)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .buttonStyle(.appInteractive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(FeatureAccent.clutter.gradient)
                        }
                }
                .padding(18)
            }
            .frame(width: 400)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
            }
        }
        .transition(.opacity)
    }
}

struct UninstallProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView().controlSize(.large)

                Text("Moving to Trash…")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(34)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
            }
        }
    }
}

struct UninstallResultBanner: View {
    let result: UninstallResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FeatureAccent.cleanup.solid)

            Text("\(result.app.name) removed — \(result.formattedBytesFreed) freed from \(result.filesRemoved) item(s).")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FeatureAccent.cleanup.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(FeatureAccent.cleanup.solid.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

struct InlineWarningBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FeatureAccent.boost.solid)

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FeatureAccent.boost.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(FeatureAccent.boost.solid.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - States

struct AppManagerScanningState: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(FeatureAccent.appManager.tint)
                    .frame(width: 92, height: 92)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(FeatureAccent.appManager.solid)
            }

            VStack(spacing: 7) {
                Text("Scanning your applications…")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Measuring app sizes and finding leftover support files.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            ProgressView()
                .progressViewStyle(.linear)
                .tint(FeatureAccent.appManager.solid)
                .frame(width: 240)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppManagerEmptyState: View {
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.Colors.textTertiary)

            Text("No applications found")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("CachePop couldn't read your Applications folders.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Button("Scan Again", action: onRescan)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.appManager.gradient)
                }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
