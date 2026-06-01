import SwiftUI

struct CareReadyToRunContent: View {
    let snapshot: CareScanSnapshot
    let pulse: Bool
    let onStartOver: () -> Void
    let onReview: (CareLogCategory) -> Void
    let onRun: () -> Void

    private let topResults = ScanReadyResult.topResults
    private let bottomResults = ScanReadyResult.bottomResults

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 1100, 0.82), 1.04)

            VStack(spacing: 0) {
                ReadyTopBar(onStartOver: onStartOver)

                Text("Your tasks are ready to run. Look what we found:")
                    .font(.system(size: 36 * scale, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.Care.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 58 * scale)
                    .padding(.bottom, 36 * scale)

                VStack(spacing: 16 * scale) {
                    HStack(spacing: 16 * scale) {
                        ForEach(topResults) { result in
                            ReadyTaskCard(
                                result: result,
                                snapshot: snapshot,
                                scale: scale,
                                onReview: onReview
                            )
                        }
                    }
                    .frame(height: 210 * scale)

                    HStack(spacing: 16 * scale) {
                        ForEach(bottomResults) { result in
                            ReadyTaskCard(
                                result: result,
                                snapshot: snapshot,
                                scale: scale,
                                onReview: onReview
                            )
                        }
                    }
                    .frame(height: 218 * scale)
                }
                .padding(.horizontal, 34)

                Spacer(minLength: 28)
            }
            .overlay(alignment: .bottom) {
                ReadyRunButton(pulse: pulse, action: onRun)
                    .frame(width: 108 * scale, height: 108 * scale)
                    .padding(.bottom, 28 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

private struct ReadyTopBar: View {
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            Button(action: onStartOver) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .bold))

                    Text("Start Over")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppTheme.Care.headingMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start over")

            Spacer()

            Button("Unlock Full Version") {}
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(AppTheme.Care.actionGradient)
                        .shadow(color: AppTheme.Care.actionShadow, radius: 12, y: 5)
                }
                .raisedButtonChrome(cornerRadius: 21)
        }
        .frame(height: 48)
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            Text("Care")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Care.headingMuted)
        }
    }
}

private struct ReadyTaskCard: View {
    let result: ScanReadyResult
    let snapshot: CareScanSnapshot
    let scale: CGFloat
    let onReview: (CareLogCategory) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: result.backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1.1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 8)

            ResultCardBadge(
                result: ScanResult(
                    category: result.category,
                    title: result.title,
                    value: result.value,
                    status: result.status,
                    symbolName: result.symbolName,
                    backgroundColors: result.backgroundColors,
                    badgeColors: result.badgeColors,
                    badgeRotation: result.badgeRotation,
                    isWide: result.isWide
                )
            )
            .frame(width: result.isWide ? 154 * scale : 142 * scale, height: result.isWide ? 154 * scale : 142 * scale)
            .offset(x: result.isWide ? 38 * scale : 24 * scale, y: result.isWide ? -24 * scale : -28 * scale)
            .opacity(0.9)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if result.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18 * scale, weight: .black))
                            .foregroundStyle(AppTheme.Colors.inverseText)
                            .frame(width: 28 * scale, height: 28 * scale)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(.white.opacity(0.16), lineWidth: 1)
                                    }
                            }
                    }

                    Text(result.title)
                        .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Care.cardSubtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Text(value)
                    .font(.system(size: 36 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Care.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(status)
                    .font(.system(size: 17 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Care.cardSubtext)
                    .padding(.top, 10 * scale)

                if result.showsReview {
                    HStack {
                        Spacer()

                        Button("View") {
                            onReview(result.category)
                        }
                            .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.inverseText)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 18 * scale)
                            .frame(height: 34 * scale)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.Care.actionGradient)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(.white.opacity(0.26), lineWidth: 1)
                                    }
                            }
                            .raisedButtonChrome(cornerRadius: 8)
                    }
                    .padding(.top, -26 * scale)
                }
            }
            .padding(22 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var value: String {
        switch result.category {
        case .cleanup:
            snapshot.formattedCacheSize
        case .protection:
            snapshot.protectionSummary
        case .performance:
            snapshot.startupSummary
        case .applications:
            snapshot.appSummary
        case .myClutter:
            snapshot.clutterSummary
        case .all:
            result.value
        }
    }

    private var status: String {
        switch result.category {
        case .cleanup:
            "to clean"
        case .protection:
            "to review"
        case .performance:
            "to review"
        case .applications:
            "checked"
        case .myClutter:
            "to remove"
        case .all:
            result.status
        }
    }
}

private struct ReadyRunButton: View {
    let pulse: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.Care.actionGlow)
                    .scaleEffect(pulse ? 1.26 : 0.92)
                    .blur(radius: 16)

                Circle()
                    .fill(
                        AppTheme.Care.actionGradient
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.82), lineWidth: 2)
                    }
                    .shadow(color: Color(hex: 0xE15CFF).opacity(0.48), radius: 24, y: 8)

                Text("Run")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
            }
            .contentShape(Circle())
            .raisedCircleButtonChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Run ready tasks")
    }
}
