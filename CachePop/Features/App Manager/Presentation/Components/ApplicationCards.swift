import SwiftUI

struct ApplicationUpdateCard: View {
    var body: some View {
        ApplicationCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("3 Application Updates")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.bottom, 9)

                Text("Available")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.bottom, 14)

                Text("Update your software to keep up with the latest features and compatibility improvements.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
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

struct ApplicationWideCard: View {
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
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
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

struct ApplicationSmallCard: View {
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

struct ApplicationCardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .cardHoverChrome(scale: 1.008)
    }
}

struct ApplicationsActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let style: Style

    var body: some View {
        Button(title) {}
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(style == .primary ? Color.white : AppTheme.Colors.textPrimary)
            .buttonStyle(.appInteractive)
            .frame(width: style == .primary ? 82 : 74, height: 35)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(style == .primary ? AnyShapeStyle(FeatureAccent.appManager.gradient) : AnyShapeStyle(AppTheme.Colors.glassBg))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
            }
            .raisedButtonChrome(cornerRadius: 9)
    }
}
