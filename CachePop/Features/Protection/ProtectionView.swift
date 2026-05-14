//
//  ProtectionView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct ProtectionView: View {
    var onStartOver: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ProtectionTopBar(onStartOver: onStartOver)

            VStack(spacing: 18) {
                Text("4 threats found.")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Remove threats and manage your privacy items.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button("Review Found Threats") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.white.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .padding(.top, 14)
            }
            .padding(.top, 72)

            Spacer(minLength: 54)

            ProtectionThreatLayout()
                .padding(.leading, 28)
                .padding(.trailing, 24)
                .padding(.bottom, 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProtectionTopBar: View {
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
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 30)
        .padding(.top, 26)
        .padding(.horizontal, 34)
        .overlay(alignment: .bottom) {
            Text("Protection")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
    }
}

private struct ProtectionThreatLayout: View {
    var body: some View {
        HStack(spacing: 16) {
            ProtectionSummaryCard()
                .frame(width: 315)

            VStack(spacing: 16) {
                ProtectionWideCard(
                    title: "1 780 Google Chrome Temporary Files Found",
                    subtitle: "Remove your browser data to free up space and improve your privacy.",
                    accessory: .chrome
                )

                ProtectionWideCard(
                    title: "20 Recent Items Found",
                    subtitle: "Remove the traces of your recent activities by cleaning up these lists.",
                    accessory: .document
                )
            }
        }
    }
}

private struct ProtectionSummaryCard: View {
    var body: some View {
        ProtectionCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("4 Threats found")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                Text("Remove them at your soonest to stay protected.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ThreatCluster()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)

                Spacer()

                HStack(spacing: 10) {
                    Spacer()
                    ProtectionActionButton(title: "Review", style: .secondary)
                    ProtectionActionButton(title: "Remove", style: .primary)
                }
            }
            .padding(22)
        }
    }
}

private struct ProtectionWideCard: View {
    enum Accessory {
        case chrome
        case document
    }

    let title: String
    let subtitle: String
    let accessory: Accessory

    var body: some View {
        ProtectionCardContainer {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    HStack(spacing: 10) {
                        Spacer()
                        ProtectionActionButton(title: "Review", style: .secondary)
                        ProtectionActionButton(title: "Remove", style: .primary)
                    }
                }
                .padding(22)
                .padding(.trailing, 70)

                switch accessory {
                case .chrome:
                    ChromeBadge()
                        .frame(width: 44, height: 44)
                        .padding(.top, 24)
                        .padding(.trailing, 24)
                case .document:
                    DocumentBadge()
                        .frame(width: 44, height: 44)
                        .padding(.top, 24)
                        .padding(.trailing, 24)
                }
            }
        }
        .frame(height: 170)
    }
}

private struct ProtectionCardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                        LinearGradient(
                            colors: [
                            Color(hex: 0x6F7FD6).opacity(0.72),
                            Color(hex: 0x596CDD).opacity(0.74),
                            Color(hex: 0x181052).opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ProtectionActionButton: View {
    enum ButtonStyleKind {
        case primary
        case secondary
    }

    let title: String
    let style: ButtonStyleKind

    var body: some View {
        Button(title) {}
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(style == .primary ? .black : .white)
            .buttonStyle(.plain)
            .frame(width: style == .primary ? 74 : 72, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style == .primary ? .white.opacity(0.94) : .white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(style == .primary ? 0 : 0.12), lineWidth: 1)
                    }
            }
    }
}

private struct ThreatCluster: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xEEF2FF),
                            Color(hex: 0x809FFF),
                            Color(hex: 0x3320A8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.28), radius: 7, y: 6)

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 53, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.88))
                .rotationEffect(.degrees(-8))

            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xB7C8FF),
                                Color(hex: 0x4B3BD2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                Image(systemName: "door.left.hand.closed")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .offset(x: 93, y: 0)
            .shadow(color: .black.opacity(0.25), radius: 5, y: 4)

            ZStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: 0xDCE6FF), Color(hex: 0x5548DC))

                Circle()
                    .fill(Color(hex: 0xDCE4FF))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: 0x3620A8))
                    }
                    .offset(x: 17, y: 18)
            }
            .offset(x: -100, y: 14)
            .shadow(color: .black.opacity(0.22), radius: 5, y: 4)
        }
    }
}

private struct ChromeBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 4, y: 4)

            Circle()
                .trim(from: 0, to: 0.33)
                .stroke(Color(hex: 0xF44336), lineWidth: 17)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.33, to: 0.66)
                .stroke(Color(hex: 0xFFCE43), lineWidth: 17)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.66, to: 1)
                .stroke(Color(hex: 0x35A852), lineWidth: 17)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color(hex: 0x4285F4))
                .frame(width: 23, height: 23)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                }
        }
        .padding(6)
    }
}

private struct DocumentBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xB7C8FF),
                            Color(hex: 0x4B3BD2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.22), radius: 4, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.white.opacity(0.82))
                            .frame(width: 3.5, height: 3.5)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(.white.opacity(0.82))
                            .frame(width: 20, height: 3.5)
                    }
                }
            }
        }
    }
}

private struct ProtectionSidebar: View {
    private let items: [ProtectionSidebarItem] = [
        .smartCare,
        .cleanup,
        .protection,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
                .frame(height: 118)

            ForEach(items) { item in
                ProtectionSidebarIcon(item: item)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.24))
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.82), Color(hex: 0xDCE4FF).opacity(0.6))
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

private struct ProtectionSidebarIcon: View {
    let item: ProtectionSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .protection ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .protection ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0xFF64BF).opacity(item == .protection ? 0.95 : 0.45))
                .frame(width: 58, height: 58)

            if item == .protection {
                Circle()
                    .fill(Color(hex: 0xFFD633))
                    .frame(width: 16, height: 16)
                    .shadow(color: Color(hex: 0xFFD633).opacity(0.75), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private enum ProtectionSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case protection
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
        case .protection:
            "hand.raised.fill"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

private struct ProtectionBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xB22B88),
                    Color(hex: 0x980052),
                    Color(hex: 0x480018)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xFF2DBD).opacity(0.46),
                    Color(hex: 0xA30066).opacity(0.16),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.72),
                startRadius: 18,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xA31774).opacity(0.3),
                    .clear
                ],
                center: UnitPoint(x: 0.58, y: 0.16),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.04),
                    .black.opacity(0.34)
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
    ProtectionView()
        .frame(width: 1180, height: 760)
}
