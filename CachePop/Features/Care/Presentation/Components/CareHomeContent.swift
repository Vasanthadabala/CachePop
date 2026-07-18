import SwiftUI

struct CareHomeContent: View {
    let snapshot: CareScanSnapshot
    let scale: CGFloat
    let onScan: () -> Void
    let onSelectFeature: (CareSidebarItem) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting)
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text("Here's how your Mac is doing today.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(.top, 8)

                    heroCard

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "This Mac")

                        HStack(spacing: 14) {
                            StatTile(accent: .cleanup, symbolName: "trash.fill", value: snapshot.formattedCacheSize, label: "Junk found")
                            StatTile(accent: .boost, symbolName: "bolt.fill", value: "\(snapshot.startupItems)", label: "Startup items")
                            StatTile(accent: .appManager, symbolName: "square.grid.2x2.fill", value: "\(snapshot.appsChecked)", label: "Apps checked")
                            StatTile(accent: .clutter, symbolName: "folder.fill", value: "\(snapshot.largeFiles + snapshot.duplicateFiles)", label: "Clutter files")
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "Quick Actions")

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                            FeatureShortcutCard(
                                accent: .cleanup,
                                title: "Junk Cleaner",
                                subtitle: "Free up disk space",
                                action: { onSelectFeature(.cleanup) }
                            )
                            FeatureShortcutCard(
                                accent: .boost,
                                title: "Boost",
                                subtitle: "Speed up your Mac",
                                action: { onSelectFeature(.performance) }
                            )
                            FeatureShortcutCard(
                                accent: .appManager,
                                title: "App Manager",
                                subtitle: "Manage applications",
                                action: { onSelectFeature(.applications) }
                            )
                            FeatureShortcutCard(
                                accent: .clutter,
                                title: "Clutter",
                                subtitle: "Sort large & duplicate files",
                                action: { onSelectFeature(.myClutter) }
                            )
                        }
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 40)
            }

            Button("Unlock Full Version") {}
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.dashboard.gradient)
                }
                .raisedButtonChrome(cornerRadius: 21)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 26)
                .padding(.trailing, 28)
        }
    }

    private var heroCard: some View {
        HStack(spacing: 30) {
            HealthScoreRing(progress: healthProgress, status: healthStatus, lineWidth: 12)
                .frame(width: 148, height: 148)

            VStack(alignment: .leading, spacing: 12) {
                Text(heroTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(heroSubtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Run Smart Scan", action: onScan)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .buttonStyle(.appInteractive)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FeatureAccent.dashboard.gradient)
                    }
                    .accentGlow(.dashboard, radius: 16, y: 6)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(26)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var hasScannedBefore: Bool {
        snapshot != .empty
    }

    private var healthStatus: HealthStatus {
        guard hasScannedBefore else { return .unknown }
        return snapshot.hasFindings ? .attention : .good
    }

    private var healthProgress: Double {
        switch healthStatus {
        case .unknown:
            0
        case .attention:
            0.55
        case .good:
            1.0
        }
    }

    private var heroTitle: String {
        switch healthStatus {
        case .unknown:
            "Let's check up on your Mac"
        case .attention:
            "Your Mac could use some care"
        case .good:
            "Your Mac is in great shape"
        }
    }

    private var heroSubtitle: String {
        switch healthStatus {
        case .unknown:
            "Run a Smart Scan to check junk, protection, performance, apps, and clutter in one pass."
        case .attention:
            "Your last scan found things worth cleaning up. Head to Smart Care to review and apply them."
        case .good:
            "Nothing urgent right now — nice work keeping things tidy."
        }
    }
}
