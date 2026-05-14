//
//  PerformanceView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct PerformanceView: View {
    var onDone: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            Text("Performance")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 26)

            PerformanceCompletePanel(onDone: onDone)
                .padding(.leading, 92)
                .padding(.trailing, 82)
                .padding(.top, 118)
                .padding(.bottom, 82)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PerformanceCompletePanel: View {
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
                            .stroke(.white.opacity(0.11), lineWidth: 1)
                    }

                PerformanceBadge()
                    .frame(width: min(proxy.size.width * 0.46, 410))
                    .offset(x: -proxy.size.width * 0.1, y: -16)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Removal complete!")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 20) {
                        RocketBadge()
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("8 background items")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("successfully removed")
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

                HStack(spacing: 16) {
                    Button("Manage More Items") {}
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .frame(width: 154, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.13), lineWidth: 1)
                                }
                        }

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
                }
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

private struct PerformanceBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black.opacity(0.22))
                .frame(width: 356, height: 76)
                .blur(radius: 10)
                .rotationEffect(.degrees(2))
                .offset(y: 130)

            PerformanceChevronShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF2F5FF),
                            Color(hex: 0x83A1FF),
                            Color(hex: 0x3922B2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    PerformanceChevronShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.42),
                                    Color(hex: 0xB7C8FF).opacity(0.56),
                                    .black.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                }
                .shadow(color: .black.opacity(0.34), radius: 13, y: 10)

            PerformanceChevronShape()
                .fill(.white.opacity(0.18))
                .blur(radius: 9)
                .scaleEffect(0.82)
                .offset(x: 18, y: -42)

            Image(systemName: "bolt.fill")
                .font(.system(size: 112, weight: .heavy))
                .rotationEffect(.degrees(7))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.96),
                            Color(hex: 0xDDE5FF).opacity(0.86)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: 0x3E1ED0).opacity(0.45), radius: 12, y: 12)
        }
        .aspectRatio(1.15, contentMode: .fit)
    }
}

private struct PerformanceChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.17))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.07),
            control: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY - rect.height * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.17),
            control: CGPoint(x: rect.maxX - rect.width * 0.29, y: rect.minY - rect.height * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.18),
            control: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.35),
            control: CGPoint(x: rect.maxX - rect.width * 0.23, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY - rect.height * 0.18),
            control: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.17),
            control: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

private struct RocketBadge: View {
    var body: some View {
        ZStack {
            ShieldShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xDCE6FF),
                            Color(hex: 0x7EA0FF),
                            Color(hex: 0x3320A8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 4)

            Image(systemName: "rocket.fill")
                .font(.system(size: 25, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: 0xE8ECFF), Color(hex: 0xAFC2FF))
        }
    }
}

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.72))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.24))
        path.closeSubpath()
        return path
    }
}

private struct PerformanceSidebar: View {
    private let items: [PerformanceSidebarItem] = [
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
                PerformanceSidebarIcon(item: item)
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

private struct PerformanceSidebarIcon: View {
    let item: PerformanceSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .performance ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .performance ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9), Color(hex: 0xFFB159).opacity(item == .performance ? 0.95 : 0.45))
                .frame(width: 58, height: 58)

            if item == .performance {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private enum PerformanceSidebarItem: String, Identifiable {
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

private struct PerformanceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x7C1C05),
                    Color(hex: 0xD43C00),
                    Color(hex: 0x9C2300)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xFF8C1A).opacity(0.5),
                    Color(hex: 0xA83400).opacity(0.2),
                    .clear
                ],
                center: UnitPoint(x: 0.42, y: 0.72),
                startRadius: 18,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xE4570B).opacity(0.4),
                    .clear
                ],
                center: UnitPoint(x: 0.63, y: 0.08),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.06),
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
    PerformanceView()
        .frame(width: 1180, height: 760)
}
