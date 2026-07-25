//
//  AssistantView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AssistantView: View {
    var onNavigate: (CareSidebarItem) -> Void = { _ in }

    @State private var viewModel = AssistantViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                HStack(alignment: .top, spacing: 18) {
                    MacHealthPanel(viewModel: viewModel)
                        .frame(width: 330)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: viewModel.isLoading ? "Checking" : "Recommendations")

                        if viewModel.isLoading {
                            AssistantLoadingCard()
                        } else if viewModel.tips.isEmpty {
                            AssistantAllClearCard()
                        } else {
                            ForEach(viewModel.tips) { tip in
                                AssistantTipCard(tip: tip) {
                                    viewModel.perform(tip.action, navigate: onNavigate)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 30)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            viewModel.load()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Assistant")
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(viewModel.healthSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Button {
                viewModel.load()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text("Refresh")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(FeatureAccent.assistant.solid)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.assistant.tint)
                }
            }
            .buttonStyle(.appInteractive)
        }
    }
}

// MARK: - Health Panel

struct MacHealthPanel: View {
    @Bindable var viewModel: AssistantViewModel

    var body: some View {
        VStack(spacing: 22) {
            HealthScoreRing(
                progress: viewModel.healthScore,
                status: viewModel.healthStatus,
                lineWidth: 13
            )
            .frame(width: 168, height: 168)
            .padding(.top, 4)

            VStack(spacing: 5) {
                Text(viewModel.healthHeadline)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                if !viewModel.isLoading {
                    Text(viewModel.snapshot.osVersion)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }

            Divider().overlay(AppTheme.Colors.border)

            VStack(spacing: 14) {
                SystemReadingRow(
                    accent: .clutter,
                    symbolName: "internaldrive.fill",
                    label: "Storage",
                    value: viewModel.isLoading ? "—" : "\(viewModel.snapshot.disk.formattedAvailable) free",
                    fraction: viewModel.snapshot.disk.usedFraction
                )

                SystemReadingRow(
                    accent: .appManager,
                    symbolName: "memorychip.fill",
                    label: "Memory",
                    value: viewModel.isLoading ? "—" : "\(viewModel.snapshot.memory.formattedUsed) used",
                    fraction: viewModel.snapshot.memory.usedFraction
                )

                if viewModel.snapshot.battery.isPresent {
                    SystemReadingRow(
                        accent: .cleanup,
                        symbolName: "battery.100",
                        label: "Battery health",
                        value: viewModel.isLoading ? "—" : "\(viewModel.snapshot.battery.healthPercent)%",
                        fraction: Double(viewModel.snapshot.battery.healthPercent) / 100
                    )
                }

                SystemReadingRow(
                    accent: .boost,
                    symbolName: "clock.fill",
                    label: "Uptime",
                    value: viewModel.isLoading ? "—" : viewModel.snapshot.uptimeText,
                    fraction: nil
                )
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        }
    }
}

struct SystemReadingRow: View {
    let accent: FeatureAccent
    let symbolName: String
    let label: String
    let value: String
    /// When present, draws a usage meter beneath the row.
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent.solid)
                    .frame(width: 18)

                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.Colors.border)

                        Capsule()
                            .fill(accent.solid)
                            .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 3))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

// MARK: - Tip Cards

struct AssistantTipCard: View {
    let tip: AssistantTip
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tip.severity.accent.tint)
                    .frame(width: 44, height: 44)

                Image(systemName: tip.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tip.severity.accent.solid)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tip.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tip.body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = tip.actionTitle {
                    Button(actionTitle, action: onAction)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .buttonStyle(.appInteractive)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            Capsule(style: .continuous)
                                .fill(tip.severity.accent.gradient)
                        }
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
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

struct AssistantLoadingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)

            Text("Reading battery, storage, memory, and uptime…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer()
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
        }
    }
}

struct AssistantAllClearCard: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(FeatureAccent.cleanup.tint)
                    .frame(width: 46, height: 46)

                Image(systemName: "checkmark")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(FeatureAccent.cleanup.solid)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing needs attention")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Battery, storage, memory, and uptime all look healthy.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(18)
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

#Preview {
    AssistantView()
        .frame(width: 1180, height: 760)
}
