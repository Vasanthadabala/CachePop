import SwiftUI

struct MacHealthPanel: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 14, y: 5)

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                MacHealthRing()
                    .frame(width: 380, height: 380)

                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac Health:")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        HStack(spacing: 8) {
                            Text("Requires Attention")
                                .font(.system(size: 26, weight: .regular, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)

                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }

                    Text("Your Mac is not doing well. Run some maintenance to bring it back into shape.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.bottom, 34)
            }
        }
    }
}

struct MacHealthRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Colors.border, lineWidth: 26)
                .blur(radius: 4)

            Circle()
                .stroke(FeatureAccent.assistant.gradient, lineWidth: 8)

            Circle()
                .trim(from: 0.02, to: 0.78)
                .stroke(AppTheme.Colors.border, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-48))

            VStack(spacing: 22) {
                LaptopIllustration()
                    .frame(width: 175, height: 120)

                Text("Your Mac")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .offset(y: 16)
        }
    }
}

struct LaptopIllustration: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xFFF8BA),
                            Color(hex: 0xF0C37B)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 130, height: 84)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: 0x7B4596).opacity(0.72))
                        .frame(width: 25, height: 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: 0x3E2C82).opacity(0.86), lineWidth: 2)
                }
                .offset(y: -24)

            Path { path in
                path.move(to: CGPoint(x: 26, y: 76))
                path.addLine(to: CGPoint(x: 149, y: 76))
                path.addLine(to: CGPoint(x: 168, y: 101))
                path.addLine(to: CGPoint(x: 7, y: 101))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.Colors.textTertiary,
                        AppTheme.Colors.accentDeep,
                        AppTheme.Colors.accentStrong
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: 0x191646).opacity(0.78))
                .frame(width: 96, height: 12)
                .offset(y: -13)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: 0x9B88E8))
                .frame(width: 176, height: 9)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.28))
                        .frame(height: 1)
                }
        }
    }
}

struct AssistantTipsPane: View {
    private let tips = AssistantTip.samples

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 16) {
                ForEach(tips) { tip in
                    AssistantTipCard(tip: tip)
                        .frame(height: 197)
                }

                AssistantTipCard(tip: .extra)
                    .frame(height: 152)
                    .opacity(0.42)
            }
            .padding(.trailing, 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.Colors.border)
                .frame(width: 5, height: 365)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.Colors.glassBorder)
                        .frame(width: 5, height: 98)
                        .padding(.top, 2)
                }
        }
    }
}

struct AssistantTipCard: View {
    let tip: AssistantTip

    var body: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            .overlay {
                HStack(alignment: .top, spacing: 28) {
                    TipIcon(kind: tip.icon)
                        .frame(width: 52, height: 52)
                        .padding(.top, 49)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(tip.title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Text(tip.body)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        if let buttonTitle = tip.buttonTitle {
                            HStack {
                                Spacer()

                                Button(buttonTitle) {}
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 20)
                                    .frame(height: 36)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(FeatureAccent.assistant.gradient)
                                    }
                                    .raisedButtonChrome(cornerRadius: 8)
                                    .buttonStyle(.appInteractive)
                            }
                        }
                    }
                    .padding(.top, 42)
                    .padding(.bottom, 21)
                }
                .padding(.horizontal, 30)
            }
    }
}

struct TipIcon: View {
    enum Kind {
        case battery
        case menu
        case restart
        case cleanup
    }

    let kind: Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
                .shadow(color: glow, radius: 17)

            switch kind {
            case .battery:
                Image(systemName: "battery.25")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFD45C))
            case .menu:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: 0x46208F))
                        .frame(width: 44, height: 32)

                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            MiniMenuBlock()
                            MiniMenuBlock()
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: 0x06D6B7))
                                .frame(width: 4, height: 4)
                            Circle()
                                .fill(Color(hex: 0x168CFF))
                                .frame(width: 4, height: 4)
                        }
                    }

                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 19, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.Colors.textPrimary, AppTheme.Colors.textSecondary)
                        .offset(x: 14, y: 15)
                }
            case .restart:
                Image(systemName: "power")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            case .cleanup:
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))
            }
        }
    }

    private var background: LinearGradient {
        switch kind {
        case .battery:
            LinearGradient(colors: [AppTheme.Colors.glassBg, AppTheme.Colors.border], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .menu:
            LinearGradient(colors: [AppTheme.Colors.glassBg, AppTheme.Colors.border], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .restart:
            LinearGradient(colors: [AppTheme.Colors.glassBg, AppTheme.Colors.border], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cleanup:
            LinearGradient(colors: [AppTheme.Colors.glassBg, AppTheme.Colors.border], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var glow: Color {
        Color.clear
    }
}

struct MiniMenuBlock: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: 0x1B134E))
            .frame(width: 13, height: 10)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color(hex: 0x21D687))
                    .frame(width: 3, height: 3)
                    .padding(.leading, 3)
            }
    }
}

struct AssistantSidebar: View {
    private let items: [AssistantSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 140)

            ForEach(items) { item in
                AssistantSidebarRow(item: item, isSelected: false)
            }

            Spacer()

            AssistantSidebarRow(item: .assistant, isSelected: true)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            AppTheme.Colors.sidebarBg
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(width: 1)
                }
        }
    }
}

struct AssistantSidebarRow: View {
    let item: AssistantSidebarItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color(hex: 0x111111) : AppTheme.Colors.glassBg)
                    .frame(width: 48, height: 42)

                Image(systemName: item.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textSecondary)
                    .frame(width: 38, height: 38)
            }

            Text(item.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .padding(.horizontal, 8)
    }
}

struct AssistantTip: Identifiable {
    let id = UUID()
    let icon: TipIcon.Kind
    let title: String
    let body: String
    let buttonTitle: String?

    static let samples = [
        AssistantTip(
            icon: .battery,
            title: "Critical battery health",
            body: "Your Mac's battery capacity has degraded severely. Consider a battery change.",
            buttonTitle: "Learn More..."
        ),
        AssistantTip(
            icon: .menu,
            title: "Get an overview of your Mac",
            body: "Use CachePop Menu as a powerful satellite app that helps you keep an eye on your main system readings.",
            buttonTitle: "Open CachePop Menu"
        ),
        AssistantTip(
            icon: .restart,
            title: "Restart your Mac once in a while",
            body: "It's been 19 days since your last restart. Some researchers recommend restarting regularly.",
            buttonTitle: "Learn More..."
        )
    ]

    static let extra = AssistantTip(
        icon: .cleanup,
        title: "Run quick maintenance",
        body: "Clear temporary files and refresh common services to keep your Mac feeling snappy.",
        buttonTitle: "Review"
    )
}

enum AssistantSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare:
            "Care"
        case .cleanup:
            "Junk Cleaner"
        case .performance:
            "Boost"
        case .applications:
            "App Manager"
        case .myClutter:
            "Clutter"
        case .assistant:
            "Assistant"
        }
    }

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
        case .assistant:
            "circle.grid.cross.fill"
        }
    }

    var iconColor: LinearGradient {
        LinearGradient(
            colors: [AppTheme.Colors.textSecondary, AppTheme.Colors.textSecondary],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct AssistantBackground: View {
    var body: some View {
        DarkMeshBackground()
    }
}
