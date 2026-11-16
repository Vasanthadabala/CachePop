import SwiftUI

/// Explains, in place, what Full Disk Access unlocks and how to grant it.
///
/// CachePop works without it — developer caches, Xcode data and simulators are all readable —
/// but macOS hides the Trash and some app caches from apps that don't have it. This shows only
/// when a scan actually ran into one of those folders.
struct PermissionPromptView: View {
    let reason: String
    var onOpenSettings: () -> Void = { PermissionsManager.shared.requestFullDiskAccess() }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            IconTile(symbolName: "lock", size: AppTheme.Layout.rowIcon)

            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access needed for some items")
                    .font(AppTheme.Typography.headline)
                Text(reason)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("System Settings › Privacy & Security › Full Disk Access › CachePop, then scan again.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.Spacing.xs)

            Button("Open Settings", action: onOpenSettings)
                .controlSize(.regular)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 10)
        .card()
    }
}

#Preview {
    PermissionPromptView(reason: "macOS keeps the Trash private. Without access CachePop can't see or empty it.")
        .padding()
        .frame(width: 640)
}
