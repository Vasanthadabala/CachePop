import SwiftUI

struct CleanupIntroContent: View {
    let onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.82), 1.05)

            ZStack {
                CleanupTopBar(title: "", showsStartOver: false, onStartOver: {})

                HStack(spacing: 74 * scale) {
                    CleanupDisk()
                        .frame(width: 390 * scale, height: 390 * scale)

                    VStack(alignment: .leading, spacing: 30 * scale) {
                        VStack(alignment: .leading, spacing: 18 * scale) {
                            Text("Junk Cleaner")
                                .font(.system(size: 54 * scale, weight: .light, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)

                            Text("Clean your system to achieve maximum\nperformance and reclaim more free space.")
                                .font(.system(size: 22 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                                .lineSpacing(6)
                        }
                        .padding(.bottom, 16 * scale)

                        CleanupFeatureRow(symbolName: "archivebox.fill", title: "System Junk", scale: scale)
                        CleanupFeatureRow(symbolName: "envelope.fill", title: "Mail Attachments", scale: scale)
                        CleanupFeatureRow(symbolName: "trash.fill", title: "Trash Bins", scale: scale)
                    }
                    .frame(width: 430 * scale, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -26 * scale)

                CleanupCircleButton(title: "Scan", action: onScan)
                    .frame(width: 104 * scale, height: 104 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 22 * scale)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct CleanupFeatureRow: View {
    let symbolName: String
    let title: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                Circle()
                    .fill(FeatureAccent.cleanup.tint)
                    .frame(width: 34 * scale, height: 34 * scale)

                Image(systemName: symbolName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(FeatureAccent.cleanup.solid)
            }

            Text(title)
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
        }
    }
}

struct CleanupScanningContent: View {
    let progress: Double
    let currentPath: String
    let onStartOver: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.82), 1.05)

            ZStack {
                CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: onStartOver)

                VStack(spacing: 0) {
                    CleanupDisk()
                        .frame(width: 430 * scale, height: 430 * scale)
                        .padding(.top, 94 * scale)

                    Spacer(minLength: 42)

                    Text("Looking for junk...")
                        .font(.system(size: 46 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(currentPath)
                        .font(.system(size: 20 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .padding(.top, 18 * scale)
                        .padding(.horizontal, 70)

                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(FeatureAccent.cleanup.solid)
                        .frame(width: min(proxy.size.width * 0.46, 420))
                        .scaleEffect(x: 1, y: 0.72, anchor: .center)
                        .padding(.top, 24 * scale)

                    Spacer(minLength: 96)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct CleanupFoundContent: View {
    let snapshot: CareScanSnapshot
    let onStartOver: () -> Void
    let onClean: () -> Void

    private var cards: [CleanupJunkSummary] {
        CleanupJunkSummary.makeSummaries(from: snapshot)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.8), 1.04)
            let hasFindings = snapshot.cacheItems > 0

            ZStack {
                CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: onStartOver)

                VStack(spacing: 0) {
                    CleanupDisk()
                        .frame(width: 210 * scale, height: 210 * scale)
                        .padding(.top, 104 * scale)

                    Text(hasFindings ? "There are \(snapshot.formattedCacheSize) of junk files on your Mac." : "No junk files found on your Mac.")
                        .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.top, 78 * scale)

                    Button("Review All Junk") {}
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .buttonStyle(.appInteractive)
                        .padding(.horizontal, 24 * scale)
                        .frame(height: 44 * scale)
                        .background {
                            Capsule(style: .continuous)
                                .fill(FeatureAccent.cleanup.gradient)
                        }
                        .accentGlow(.cleanup, radius: 12, y: 5)
                        .raisedButtonChrome(cornerRadius: 22)
                        .padding(.top, 26 * scale)
                        .opacity(hasFindings ? 1 : 0.55)
                        .disabled(!hasFindings)

                    Spacer(minLength: 40)

                    HStack(spacing: 18 * scale) {
                        ForEach(cards) { card in
                            CleanupJunkCard(
                                title: card.title,
                                subtitle: card.subtitle,
                                symbolName: card.symbolName,
                                isWide: card.isWide,
                                onClean: hasFindings && card.isPrimary ? onClean : nil
                            )
                            .frame(width: card.isWide ? nil : 300 * scale)
                            .frame(maxWidth: card.isWide ? .infinity : nil)
                        }
                    }
                    .frame(height: 202 * scale)
                    .padding(.horizontal, 42 * scale)
                    .padding(.bottom, 42 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct CleanupJunkCard: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let onClean: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FeatureAccent.cleanup.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1.2)
                }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 52, height: 52)

                Image(systemName: symbolName)
                    .font(.system(size: 29, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.95))
            }
            .padding(.top, 22)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
                    .lineLimit(isWide ? 1 : 2)
                    .minimumScaleFactor(0.72)
                    .padding(.bottom, subtitle == nil ? 0 : 14)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.72))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                HStack(spacing: 10) {
                    Spacer()

                    Button("Review") {}
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                        .buttonStyle(.appInteractive)
                        .frame(width: 78, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                }
                        }
                        .raisedButtonChrome(cornerRadius: 8)

                    if let onClean {
                        Button("Clean", action: onClean)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.inverseText)
                            .buttonStyle(.appInteractive)
                            .frame(width: 74, height: 36)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.16))
                            }
                            .raisedButtonChrome(cornerRadius: 8)
                    }
                }
            }
            .padding(22)
            .padding(.trailing, isWide ? 88 : 52)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CleanupTopBar: View {
    let title: String
    let showsStartOver: Bool
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            if showsStartOver {
                Button(action: onStartOver) {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))

                        Text("Start Over")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                }
                .buttonStyle(.appInteractive)
            }

            Spacer()

            Button("Unlock Full Version") {}
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.cleanup.gradient)
                }
                .accentGlow(.cleanup, radius: 12, y: 5)
                .raisedButtonChrome(cornerRadius: 21)
        }
        .frame(height: 48)
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CleanupCircleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(FeatureAccent.cleanup.gradient)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 2)
                    }
                    .accentGlow(.cleanup, radius: 28, y: 9)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
            }
            .contentShape(Circle())
            .raisedCircleButtonChrome()
        }
        .buttonStyle(.appInteractive)
    }
}

struct CleanupCompletePanel: View {
    let cleanedSize: String
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(FeatureAccent.cleanup.tint.opacity(0.6))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.05), radius: 14, y: 5)

                CleanupDisk()
                    .frame(width: min(proxy.size.width * 0.46, 390))
                    .offset(x: -proxy.size.width * 0.11, y: -4)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Cleanup complete!")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(FeatureAccent.cleanup.gradient)
                                .frame(width: 46, height: 46)

                            Image(systemName: "trash.fill")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(cleanedSize) of Junk")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("successfully cleaned")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                        }
                    }
                }
                .frame(width: proxy.size.width * 0.46, alignment: .leading)
                .offset(x: proxy.size.width * 0.45)

                Button("View Log") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .buttonStyle(.appInteractive)
                    .padding(.leading, 38)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FeatureAccent.cleanup.gradient)
                            }
                    }
                    .buttonStyle(.appInteractive)
                    .accentGlow(.cleanup, radius: 10, y: 4)
                    .raisedButtonChrome(cornerRadius: 12)
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

struct CleanupDisk: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.16))
                .frame(width: 360, height: 74)
                .blur(radius: 12)
                .offset(y: 126)

            Circle()
                .fill(FeatureAccent.cleanup.gradient)
                .overlay {
                    Circle()
                        .stroke(FeatureAccent.cleanup.deep.opacity(0.5), lineWidth: 3)
                }
                .accentGlow(.cleanup, radius: 22, y: 12)

            Circle()
                .fill(.white)
                .frame(width: 142, height: 142)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Image(systemName: "checkmark")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(FeatureAccent.cleanup.solid)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CleanupSidebar: View {
    private let items: [CleanupSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
                .frame(height: 118)

            ForEach(items) { item in
                CleanupSidebarIcon(item: item)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.82), AppTheme.Colors.border.opacity(0.6))
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.03))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 1)
                }
        }
    }
}

struct CleanupSidebarIcon: View {
    let item: CleanupSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .cleanup ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .cleanup ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), AppTheme.Colors.textTertiary.opacity(item == .cleanup ? 0.95 : 0.45))
                .frame(width: 58, height: 58)

            if item == .cleanup {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

enum CleanupSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

struct CleanupBackground: View {
    var body: some View {
        DarkMeshBackground()
    }
}
