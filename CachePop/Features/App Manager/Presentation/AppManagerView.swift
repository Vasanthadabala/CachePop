//
//  AppManagerView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AppManagerView: View {
    var onStartOver: () -> Void = {}

    @State private var viewModel = AppManagerViewModel()

    private let accent = FeatureAccent.appManager

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ApplicationsTopBar(onStartOver: onStartOver)

                if viewModel.isScanning && !viewModel.hasScanned {
                    AppManagerScanningState()
                } else if viewModel.hasScanned && viewModel.applications.isEmpty {
                    AppManagerEmptyState(onRescan: viewModel.scanApplications)
                } else {
                    content
                }
            }

            if let pending = viewModel.pendingUninstall {
                UninstallConfirmationDialog(
                    app: pending,
                    leftoverCount: viewModel.selectedRelatedFiles.count,
                    totalSize: viewModel.formattedPendingReclaim,
                    onCancel: viewModel.cancelUninstall,
                    onConfirm: viewModel.confirmUninstall
                )
            }

            if viewModel.isUninstalling {
                UninstallProgressOverlay()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if !viewModel.hasScanned {
                viewModel.scanApplications()
            }
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            AppManagerSummaryRow(viewModel: viewModel)
                .padding(.horizontal, 28)
                .padding(.top, 18)

            AppManagerToolbar(viewModel: viewModel)
                .padding(.horizontal, 28)

            if let result = viewModel.lastUninstallResult {
                UninstallResultBanner(result: result, onDismiss: viewModel.dismissResult)
                    .padding(.horizontal, 28)
            }

            if let error = viewModel.errorMessage {
                InlineWarningBanner(message: error, onDismiss: viewModel.dismissError)
                    .padding(.horizontal, 28)
            }

            HStack(alignment: .top, spacing: 18) {
                AppListPane(viewModel: viewModel)
                    .frame(width: 360)

                AppDetailPane(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Summary

private struct AppManagerSummaryRow: View {
    @Bindable var viewModel: AppManagerViewModel

    var body: some View {
        HStack(spacing: 14) {
            StatTile(
                accent: .appManager,
                symbolName: "square.grid.2x2.fill",
                value: "\(viewModel.totalAppsFound)",
                label: "Applications"
            )

            StatTile(
                accent: .appManager,
                symbolName: "internaldrive.fill",
                value: viewModel.formattedTotalSize,
                label: "Total size"
            )

            StatTile(
                accent: .boost,
                symbolName: "moon.zzz.fill",
                value: "\(viewModel.unusedApps.count)",
                label: "Unused 60+ days"
            )

            StatTile(
                accent: .clutter,
                symbolName: "arrow.up.circle.fill",
                value: ByteCountFormatter.string(fromByteCount: viewModel.unusedSizeBytes, countStyle: .file),
                label: "Reclaimable"
            )
        }
    }
}

// MARK: - Toolbar

private struct AppManagerToolbar: View {
    @Bindable var viewModel: AppManagerViewModel

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(AppFilter.allCases) { option in
                    FilterChip(
                        title: option.title,
                        isSelected: viewModel.filter == option,
                        accent: .appManager
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            viewModel.filter = option
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)

                TextField("Search apps", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(width: 150)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.Colors.glassBg)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
            }

            Menu {
                ForEach(AppSortOrder.allCases) { option in
                    Button(option.title) { viewModel.sortOrder = option }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort: \(viewModel.sortOrder.title)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                viewModel.scanApplications()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FeatureAccent.appManager.solid)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(FeatureAccent.appManager.tint)
                    }
            }
            .buttonStyle(.appInteractive)
            .disabled(viewModel.isScanning)
            .help("Rescan applications")
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let accent: FeatureAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? accent.solid : AppTheme.Colors.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? accent.tint : AppTheme.Colors.glassBg)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(isSelected ? accent.solid.opacity(0.35) : AppTheme.Colors.border, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.appInteractive)
    }
}

#Preview {
    AppManagerView()
        .frame(width: 1180, height: 760)
}
