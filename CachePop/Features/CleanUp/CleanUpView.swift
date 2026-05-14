//
//  CleanUpView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct CleanUpView: View {
    var onDone: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            Text("Cleanup")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.top, 26)

            CleanupCompletePanel(onDone: onDone)
                .padding(.leading, 92)
                .padding(.trailing, 82)
                .padding(.top, 118)
                .padding(.bottom, 82)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CleanupCompletePanel: View {
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xEEF2FF).opacity(0.64),
                                Color(hex: 0x697DE5).opacity(0.72),
                                Color(hex: 0x181052).opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                CleanupDisk()
                    .frame(width: min(proxy.size.width * 0.46, 390))
                    .offset(x: -proxy.size.width * 0.11, y: -4)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Cleanup complete!")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: 0x7EA6FF),
                                            Color(hex: 0x3420A8)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 46, height: 46)

                            Image(systemName: "trash.fill")
                                .font(.system(size: 21, weight: .bold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("24,3 GB of Junk")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("successfully cleaned")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }
                }
                .frame(width: proxy.size.width * 0.46, alignment: .leading)
                .offset(x: proxy.size.width * 0.45)

                Button("View Log") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.leading, 38)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 72, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.93))
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

private struct CleanupDisk: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.28))
                .frame(width: 360, height: 74)
                .blur(radius: 12)
                .offset(y: 126)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xF1F4FF).opacity(0.92),
                            Color(hex: 0x7FA0FF).opacity(0.82),
                            Color(hex: 0x4834C7),
                            Color(hex: 0x0D0640)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.22),
                        startRadius: 22,
                        endRadius: 205
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.44),
                                    Color(hex: 0xB7C8FF).opacity(0.7),
                                    .black.opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                }
                .shadow(color: .black.opacity(0.38), radius: 12, y: 10)

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 310, height: 310)
                .blur(radius: 5)
                .offset(x: 54, y: -44)
                .clipShape(Circle())

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5F7FF).opacity(0.96),
                            Color(hex: 0xC6D1FF).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 142, height: 142)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)

            Circle()
                .fill(Color(hex: 0x7EA0FF))
                .frame(width: 34, height: 34)
                .offset(x: 26, y: -48)

            Capsule()
                .fill(Color(hex: 0x6557DF))
                .frame(width: 34, height: 13)
                .offset(x: 26, y: 46)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CleanupSidebar: View {
    private let items: [CleanupSidebarItem] = [
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

private struct CleanupSidebarIcon: View {
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
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0x83F07B).opacity(item == .cleanup ? 0.95 : 0.45))
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

private enum CleanupSidebarItem: String, Identifiable {
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

private struct CleanupBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x053E13),
                    Color(hex: 0x0B842E),
                    Color(hex: 0x03280E)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x00CC42).opacity(0.66),
                    Color(hex: 0x095B22).opacity(0.18),
                    .clear
                ],
                center: UnitPoint(x: 0.2, y: 0.72),
                startRadius: 18,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xA1D866).opacity(0.42),
                    .clear
                ],
                center: UnitPoint(x: 0.67, y: 0.05),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.05),
                    .black.opacity(0.4)
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
    CleanUpView()
        .frame(width: 1180, height: 760)
}
