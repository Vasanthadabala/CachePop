//
//  AssistanceView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AssistanceView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Assistant")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.top, 26)

            HStack(spacing: 16) {
                MacHealthPanel()
                    .frame(maxWidth: .infinity)

                AssistanceTipsPane()
                    .frame(width: 405)
            }
            .padding(.top, 24)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacHealthPanel: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                        LinearGradient(
                            colors: [
                            Color(hex: 0xEEF2FF).opacity(0.58),
                            Color(hex: 0x657BE5).opacity(0.72),
                            Color(hex: 0x181052).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                MacHealthRing()
                    .frame(width: 380, height: 380)

                Spacer(minLength: 48)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac Health:")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        HStack(spacing: 8) {
                            Text("Requires Attention")
                                .font(.system(size: 26, weight: .regular, design: .rounded))
                                .foregroundStyle(Color(hex: 0xBFD0FF))

                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }

                    Text("Your Mac is not doing well. Run some maintenance to bring it back into shape.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
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

private struct MacHealthRing: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0x9BB4FF).opacity(0.24),
                            Color(hex: 0x402078).opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 60,
                        endRadius: 200
                    )
                )

            Circle()
                .stroke(Color(hex: 0x9BB4FF).opacity(0.2), lineWidth: 26)
                .blur(radius: 10)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xE5ECFF),
                            Color(hex: 0x9BB4FF),
                            Color(hex: 0x6C56E8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 8
                )
                .shadow(color: Color(hex: 0x7EA0FF).opacity(0.62), radius: 12)

            Circle()
                .trim(from: 0.02, to: 0.78)
                .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-48))

            VStack(spacing: 22) {
                LaptopIllustration()
                    .frame(width: 175, height: 120)

                Text("Your Mac")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .offset(y: 16)
        }
    }
}

private struct LaptopIllustration: View {
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
                        Color(hex: 0xBCA5FF),
                        Color(hex: 0x7767CE),
                        Color(hex: 0x413577)
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

private struct AssistanceTipsPane: View {
    private let tips = AssistanceTip.samples

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 16) {
                ForEach(tips) { tip in
                    AssistanceTipCard(tip: tip)
                        .frame(height: 197)
                }

                AssistanceTipCard(tip: .extra)
                    .frame(height: 152)
                    .opacity(0.42)
            }
            .padding(.trailing, 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.white.opacity(0.24))
                .frame(width: 6, height: 365)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.34))
                        .frame(width: 6, height: 98)
                        .padding(.top, 2)
                }
        }
    }
}

private struct AssistanceTipCard: View {
    let tip: AssistanceTip

    var body: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: 0x2F166E).opacity(0.94),
                        Color(hex: 0x21115D).opacity(0.96),
                        Color(hex: 0x150845).opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .overlay {
                HStack(alignment: .top, spacing: 28) {
                    TipIcon(kind: tip.icon)
                        .frame(width: 52, height: 52)
                        .padding(.top, 49)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(tip.title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Text(tip.body)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineSpacing(4)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        if let buttonTitle = tip.buttonTitle {
                            HStack {
                                Spacer()

                                Button(buttonTitle) {}
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 20)
                                    .frame(height: 36)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.white.opacity(0.1))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                                            }
                                    }
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

private struct TipIcon: View {
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
                        .foregroundStyle(.white, Color(hex: 0xFF57D1))
                        .offset(x: 14, y: 15)
                }
            case .restart:
                Image(systemName: "power")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(Color(hex: 0xCBB0FF))
            case .cleanup:
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    private var background: LinearGradient {
        switch kind {
        case .battery:
            LinearGradient(colors: [Color(hex: 0xFF55CE), Color(hex: 0xFF6D3A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .menu:
            LinearGradient(colors: [Color(hex: 0x7C35D8), Color(hex: 0x27106E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .restart:
            LinearGradient(colors: [Color(hex: 0x8F45E7), Color(hex: 0x5929C8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cleanup:
            LinearGradient(colors: [Color(hex: 0xC657F3), Color(hex: 0x5624B2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var glow: Color {
        switch kind {
        case .battery:
            Color(hex: 0xFF4FCA).opacity(0.34)
        case .menu, .restart, .cleanup:
            Color(hex: 0x8B53FF).opacity(0.28)
        }
    }
}

private struct MiniMenuBlock: View {
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

private struct AssistanceSidebar: View {
    private let items: [AssistanceSidebarItem] = [
        .smartCare,
        .cleanup,
        .protection,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 140)

            ForEach(items) { item in
                AssistanceSidebarRow(item: item, isSelected: false)
            }

            Spacer()

            AssistanceSidebarRow(item: .assistant, isSelected: true)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
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

private struct AssistanceSidebarRow: View {
    let item: AssistanceSidebarItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.1) : .clear)
                    .frame(width: 54, height: 48)

                Image(systemName: item.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.iconColor)
                    .frame(width: 42, height: 42)
            }

            Text(item.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .frame(height: 58)
        .padding(.horizontal, isSelected ? 16 : 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }
}

private struct AssistanceTip: Identifiable {
    let id = UUID()
    let icon: TipIcon.Kind
    let title: String
    let body: String
    let buttonTitle: String?

    static let samples = [
        AssistanceTip(
            icon: .battery,
            title: "Critical battery health",
            body: "Your Mac's battery capacity has degraded severely. Consider a battery change.",
            buttonTitle: "Learn More..."
        ),
        AssistanceTip(
            icon: .menu,
            title: "Get an overview of your Mac",
            body: "Use CachePop Menu as a powerful satellite app that helps you keep an eye on your main system readings.",
            buttonTitle: "Open CachePop Menu"
        ),
        AssistanceTip(
            icon: .restart,
            title: "Restart your Mac once in a while",
            body: "It's been 19 days since your last restart. Some researchers recommend restarting regularly.",
            buttonTitle: "Learn More..."
        )
    ]

    static let extra = AssistanceTip(
        icon: .cleanup,
        title: "Run quick maintenance",
        body: "Clear temporary files and refresh common services to keep your Mac feeling snappy.",
        buttonTitle: "Review"
    )
}

private enum AssistanceSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case protection
    case performance
    case applications
    case myClutter
    case assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare:
            "Smart Care"
        case .cleanup:
            "Cleanup"
        case .protection:
            "Protection"
        case .performance:
            "Performance"
        case .applications:
            "Applications"
        case .myClutter:
            "My Clutter"
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
        case .protection:
            "hand.raised.fill"
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
            colors: [
                Color(hex: 0xFFFFFF).opacity(0.95),
                Color(hex: 0xD4C4FF).opacity(0.82),
                Color(hex: 0x75B3FF).opacity(self == .assistant ? 0.92 : 0.48)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct AssistanceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x7A14B7),
                    Color(hex: 0x3A0A87),
                    Color(hex: 0x08003A)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xB026D0).opacity(0.52),
                    Color(hex: 0x5B169D).opacity(0.22),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.26),
                startRadius: 24,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x8228DA).opacity(0.42),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.78),
                startRadius: 20,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.04),
                    .black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    AssistanceView()
        .frame(width: 1180, height: 760)
}
