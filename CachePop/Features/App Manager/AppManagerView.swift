//
//  AppManagerView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct AppManagerView: View {
    var onStartOver: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ApplicationsTopBar(onStartOver: onStartOver)

            VStack(spacing: 22) {
                Text("We've found 15 apps on your Mac.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button("Manage My Applications") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0x8EA8FF),
                                        Color(hex: 0x8EA8FF),
                                        Color(hex: 0x5E70DF)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                    }
            }
            .padding(.top, 88)

            Spacer(minLength: 76)

            ApplicationsCardsLayout()
                .padding(.leading, 28)
                .padding(.trailing, 24)
                .padding(.bottom, 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ApplicationsTopBar: View {
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
            Text("App Manager")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
    }
}

private struct ApplicationsCardsLayout: View {
    var body: some View {
        HStack(spacing: 16) {
            ApplicationUpdateCard()
                .frame(width: 315)

            VStack(spacing: 16) {
                ApplicationWideCard(
                    title: "10 Unused Applications Found",
                    subtitle: "You may not need these apps, but they use 751 MB of space in total.",
                    accessory: .unused,
                    primaryButton: nil
                )
                .frame(height: 170)

                HStack(spacing: 16) {
                    ApplicationSmallCard(
                        title: "3 Unsupported\nApplications Found",
                        accessory: .unsupported,
                        primaryButton: "Uninstall"
                    )

                    ApplicationSmallCard(
                        title: "46,4 MB of App\nLeftovers Found",
                        accessory: .leftovers,
                        primaryButton: "Remove"
                    )
                }
                .frame(height: 170)
            }
        }
    }
}

private struct ApplicationUpdateCard: View {
    var body: some View {
        ApplicationCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("3 Application Updates")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 9)

                Text("Available")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                Text("Update your software to keep up with the latest features and compatibility improvements.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack(alignment: .center, spacing: 42) {
                    AppMiniBadge(style: .cosmic)
                        .frame(width: 46, height: 46)

                    AppMainUpdateBadge()
                        .frame(width: 72, height: 72)

                    AppMiniBadge(style: .tiles)
                        .frame(width: 46, height: 46)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 58)

                HStack(spacing: 10) {
                    Spacer()
                    ApplicationsActionButton(title: "Review", style: .secondary)
                    ApplicationsActionButton(title: "Update", style: .primary)
                }
            }
            .padding(22)
        }
    }
}

private struct ApplicationWideCard: View {
    enum Accessory {
        case unused
        case unsupported
        case leftovers
    }

    let title: String
    let subtitle: String
    let accessory: Accessory
    let primaryButton: String?

    var body: some View {
        ApplicationCardContainer {
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
                        .minimumScaleFactor(0.78)

                    Spacer()

                    HStack(spacing: 10) {
                        Spacer()
                        ApplicationsActionButton(title: "Review", style: .secondary)

                        if let primaryButton {
                            ApplicationsActionButton(title: primaryButton, style: .primary)
                        }
                    }
                }
                .padding(22)
                .padding(.trailing, accessory == .unused ? 164 : 70)

                accessoryView
                    .padding(.top, 22)
                    .padding(.trailing, 20)
            }
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .unused:
            HStack(spacing: 14) {
                AppMiniBadge(style: .bars)
                    .frame(width: 46, height: 46)
                AppMiniBadge(style: .blocked)
                    .frame(width: 46, height: 46)
                AppMiniBadge(style: .pinkDisk)
                    .frame(width: 46, height: 46)
            }
        case .unsupported:
            AppMiniBadge(style: .blocked)
                .frame(width: 46, height: 46)
        case .leftovers:
            AppMiniBadge(style: .leftovers)
                .frame(width: 46, height: 46)
        }
    }
}

private struct ApplicationSmallCard: View {
    let title: String
    let accessory: ApplicationWideCard.Accessory
    let primaryButton: String

    var body: some View {
        ApplicationWideCard(
            title: title,
            subtitle: "",
            accessory: accessory,
            primaryButton: primaryButton
        )
    }
}

private struct ApplicationCardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                        LinearGradient(
                            colors: [
                            Color(hex: 0xB7C8FF).opacity(0.62),
                            Color(hex: 0x596CDD).opacity(0.74),
                            Color(hex: 0x181052).opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ApplicationsActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let style: Style

    var body: some View {
        Button(title) {}
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .frame(width: style == .primary ? 82 : 74, height: 35)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x8EA8FF).opacity(style == .primary ? 1 : 0.9),
                                Color(hex: 0x8EA8FF).opacity(0.88),
                                Color(hex: 0x5E70DF).opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(style == .primary ? .clear : .white.opacity(0.12), lineWidth: 1)
                    }
            }
    }
}

private struct AppMainUpdateBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)

            Circle()
                .stroke(Color(hex: 0xE83932), lineWidth: 12)
                .frame(width: 54, height: 54)

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 35, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(hex: 0x274CBB), .white)

            Rectangle()
                .fill(Color(hex: 0xE83932))
                .frame(width: 66, height: 9)
                .rotationEffect(.degrees(-38))
        }
    }
}

private struct AppMiniBadge: View {
    enum Style {
        case cosmic
        case tiles
        case bars
        case blocked
        case pinkDisk
        case leftovers
    }

    let style: Style

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .cosmic:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFF3DC4), Color(hex: 0x4C2BE7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 25, height: 25)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .stroke(.white.opacity(0.7), lineWidth: 2)
                        .frame(width: 39, height: 39)
                        .offset(x: -8, y: -8)
                }
        case .tiles:
            VStack(spacing: 2) {
                ForEach(0..<3) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<2) { column in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(hex: 0xEFC49B).opacity(row == column ? 1 : 0.82))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .rotationEffect(.degrees(45))
        case .bars:
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([18.0, 27.0, 38.0], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(hex: 0x98D9B9))
                        .frame(width: 5, height: height)
                }
            }
        case .blocked:
            ZStack {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFE7B4))

                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 32, height: 32)

                Rectangle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 36, height: 4)
                    .rotationEffect(.degrees(45))
            }
        case .pinkDisk:
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0xFF6AAE))
        case .leftovers:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 27, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9), Color(hex: 0x79E4FF))

                Circle()
                    .fill(Color(hex: 0x7EDBFF))
                    .frame(width: 21, height: 21)
                    .overlay {
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x2559A9))
                    }
                    .offset(x: 7, y: 7)
            }
        }
    }

    private var background: LinearGradient {
        switch style {
        case .cosmic:
            LinearGradient(colors: [Color(hex: 0x1F2768), Color(hex: 0x19194D)], startPoint: .top, endPoint: .bottom)
        case .tiles:
            LinearGradient(colors: [Color(hex: 0x34395D), Color(hex: 0x272B47)], startPoint: .top, endPoint: .bottom)
        case .bars:
            LinearGradient(colors: [Color(hex: 0x3EC873), Color(hex: 0x167B4A)], startPoint: .top, endPoint: .bottom)
        case .blocked:
            LinearGradient(colors: [Color(hex: 0xFF9C21), Color(hex: 0xA42B16)], startPoint: .top, endPoint: .bottom)
        case .pinkDisk:
            LinearGradient(colors: [Color(hex: 0xFF63A9), Color(hex: 0xF43D90)], startPoint: .top, endPoint: .bottom)
        case .leftovers:
            LinearGradient(colors: [Color(hex: 0x39B8FF), Color(hex: 0x1E63D2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct ApplicationsSidebar: View {
    private let items: [ApplicationsSidebarItem] = [
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
                ApplicationsSidebarIcon(item: item)
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

private struct ApplicationsSidebarIcon: View {
    let item: ApplicationsSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .applications ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .applications ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0x88B9FF).opacity(item == .applications ? 0.95 : 0.46))
                .frame(width: 58, height: 58)

            if item == .applications {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private enum ApplicationsSidebarItem: String, Identifiable {
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

private struct ApplicationsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x1552B4),
                    Color(hex: 0x07326F),
                    Color(hex: 0x27137A)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x2C74F2).opacity(0.55),
                    Color(hex: 0x173C97).opacity(0.26),
                    .clear
                ],
                center: UnitPoint(x: 0.16, y: 0.18),
                startRadius: 20,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x6534D3).opacity(0.58),
                    .clear
                ],
                center: UnitPoint(x: 0.16, y: 0.86),
                startRadius: 20,
                endRadius: 540
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.03),
                    .black.opacity(0.32)
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
    AppManagerView()
        .frame(width: 1180, height: 760)
}
