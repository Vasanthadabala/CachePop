import SwiftUI

struct CareSidebar: View {
    @Binding var selectedItem: CareSidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FeatureAccent.dashboard.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("CachePop")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.leading, 4)
            .padding(.bottom, 26)
            .padding(.top, 30)

            ForEach(CareSidebarItem.mainItems) { item in
                SidebarButton(
                    item: item,
                    isSelected: selectedItem == item
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedItem = item
                    }
                }
            }

            Spacer()

            // Divider
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            SidebarButton(
                item: .assistant,
                isSelected: selectedItem == .assistant
            ) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    selectedItem = .assistant
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            AppTheme.Colors.sidebarBg
                .overlay(alignment: .trailing) {
                // Simple border separator
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1)
            }
        }
    }
}

struct SidebarButton: View {
    let item: CareSidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var accent: FeatureAccent { item.accent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(accent.tint)
                            .frame(width: 32, height: 32)
                    }

                    Image(systemName: item.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? accent.solid : AppTheme.Colors.textSecondary)
                }
                .frame(width: 32, height: 32)

                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected
                            ? AppTheme.Colors.textPrimary
                            : AppTheme.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.tint.opacity(0.55))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.Colors.border.opacity(0.5))
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.title)
    }
}

enum CareSidebarItem: String, CaseIterable, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter
    case assistant

    var id: String { rawValue }

    static let mainItems: [CareSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var title: String {
        switch self {
        case .smartCare:
            "Care"
        case .cleanup:
            "Cleanup"
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

    var accent: FeatureAccent {
        switch self {
        case .smartCare:
            .dashboard
        case .cleanup:
            .cleanup
        case .performance:
            .boost
        case .applications:
            .appManager
        case .myClutter:
            .clutter
        case .assistant:
            .assistant
        }
    }

    var iconColor: LinearGradient {
        LinearGradient(
            colors: [AppTheme.Colors.textSecondary, AppTheme.Colors.textSecondary],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let selectedIconColor = LinearGradient(
        colors: [Color.white, Color.white],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct CareSectionBackground: View {
    let selectedItem: CareSidebarItem

    var body: some View {
        DarkMeshBackground()
    }
}

// SectionGradientBackground retained for API compatibility (unused visually)
struct SectionGradientBackground: View {
    let colors: [Color]
    let glow: Color
    let glowCenter: UnitPoint

    var body: some View {
        DarkMeshBackground()
    }
}

struct CareBackground: View {
    var body: some View {
        DarkMeshBackground()
    }
}

#Preview {
    CareView()
        .frame(width: 1180, height: 760)
}
