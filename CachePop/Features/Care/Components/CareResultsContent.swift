import SwiftUI

struct CareCleaningContent: View {
    let progress: Double
    let snapshot: CareScanSnapshot
    let pulse: Bool

    var body: some View {
        VStack(spacing: 0) {
            ResultsTopBar(onStartOver: {})
                .opacity(0)

            Spacer(minLength: 76)

            VStack(spacing: 18) {
                Text("Cleaning selected tasks...")
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .foregroundStyle(CachePopPalette.heading)

                Text(snapshot.currentDetail)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(CachePopPalette.headingMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
            }
            .padding(.bottom, 34)

            ZStack {
                Circle()
                    .fill(CachePopPalette.actionGlow)
                    .scaleEffect(pulse ? 1.24 : 0.96)
                    .blur(radius: 18)

                Circle()
                    .fill(CachePopPalette.actionGradient)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.82), lineWidth: 2)
                    }
                    .shadow(color: CachePopPalette.actionShadow, radius: 24, y: 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(8)

                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 12) {
                CleaningSummaryRow(title: "Junk Cleaner", value: snapshot.formattedCacheSize)
                CleaningSummaryRow(title: "Boost", value: snapshot.startupSummary)
                CleaningSummaryRow(title: "App Manager", value: snapshot.appSummary)
                CleaningSummaryRow(title: "Clutter", value: snapshot.clutterSummary)
            }
            .padding(.top, 44)
            .frame(width: 420)

            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

private struct CleaningSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(CachePopPalette.cardSubtext)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CachePopPalette.heading)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

struct CareResultsContent: View {
    let snapshot: CareScanSnapshot
    let onViewLog: () -> Void
    let onStartOver: () -> Void

    private let topResults = ScanResult.topResults
    private let bottomResults = ScanResult.bottomResults

    var body: some View {
        VStack(spacing: 0) {
            ResultsTopBar(onStartOver: onStartOver)

            Spacer(minLength: 56)

            Text("Well done! Your Mac is in great shape!")
                .font(.system(size: 38, weight: .light, design: .rounded))
                .foregroundStyle(CachePopPalette.heading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.bottom, 34)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ForEach(topResults) { result in
                        ScanResultCard(result: result, snapshot: snapshot)
                    }
                }
                .frame(height: 206)

                HStack(spacing: 16) {
                    ForEach(bottomResults) { result in
                        ScanResultCard(result: result, snapshot: snapshot)
                    }
                }
                .frame(height: 182)
            }
            .padding(.horizontal, 34)

            Spacer(minLength: 28)

            HStack {
                Spacer()

                Button("View Log", action: onViewLog)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 17)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CachePopPalette.actionGradient)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.26), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("View scan log")
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct ResultsTopBar: View {
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            Button(action: onStartOver) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))

                    Text("Start Over")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(CachePopPalette.headingMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start over")

            Spacer()
        }
        .frame(height: 28)
        .padding(.top, 26)
        .padding(.horizontal, 34)
        .overlay(alignment: .bottom) {
            Text("Care")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CachePopPalette.headingMuted)
        }
    }
}

private struct CompactResultsSidebar: View {
    var body: some View {
        VStack(spacing: 31) {
            Spacer()
                .frame(height: 160)

            ForEach(CareSidebarItem.mainItems) { item in
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(item == .smartCare ? .white.opacity(0.12) : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(item == .smartCare ? .white.opacity(0.16) : .clear, lineWidth: 1)
                        }
                        .frame(width: 56, height: 56)

                    Image(systemName: item.symbolName)
                        .font(.system(size: 23, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.iconColor)
                        .frame(width: 56, height: 56)

                    if item == .smartCare || item == .applications {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                            .offset(x: 7, y: -7)
                    }
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 34, height: 34)

                Image(systemName: CareSidebarItem.assistant.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CareSidebarItem.assistant.iconColor)
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.028))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)
                }
        }
    }
}

private struct ScanResultCard: View {
    let result: ScanResult
    let snapshot: CareScanSnapshot

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
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            ResultCardBadge(result: result)
                .frame(width: result.isWide ? 150 : 136, height: result.isWide ? 150 : 136)
                .offset(x: result.isWide ? 38 : 24, y: result.isWide ? -24 : -28)

            VStack(alignment: .leading, spacing: 0) {
                Text(result.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(CachePopPalette.cardSubtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(CachePopPalette.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))

                    Text(result.status)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CachePopPalette.cardSubtext)
                .padding(.top, 10)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var value: String {
        switch result.category {
        case .junkCleaner:
            snapshot.formattedCacheSize
        case .boost:
            snapshot.startupItems == 1 ? "1 task" : "\(snapshot.startupItems) tasks"
        case .appManager:
            "\(snapshot.appsChecked) apps checked"
        case .clutter:
            snapshot.clutterSummary
        case .all:
            result.value
        }
    }
}
