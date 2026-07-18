import SwiftUI

struct PermissionPromptView: View {
    let requiredPermission: String
    let description: String
    let iconName: String
    let onGrant: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.border.opacity(0.3))
                    .frame(width: 80, height: 80)
                
                Image(systemName: iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.top, 24)
            
            VStack(spacing: 8) {
                Text(requiredPermission)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)
            }
            
            HStack(spacing: 16) {
                Button("Later") {
                    onDismiss()
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .buttonStyle(.appInteractive)
                .frame(width: 100, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.Colors.border, lineWidth: 1)
                        }
                }
                
                Button("Grant Access") {
                    onGrant()
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .frame(width: 130, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Colors.textPrimary)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 380)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.1).ignoresSafeArea()
        PermissionPromptView(
            requiredPermission: "Full Disk Access Required",
            description: "CachePop needs Full Disk Access to scan and clean system-level caches, logs, and application data securely.",
            iconName: "lock.shield",
            onGrant: {},
            onDismiss: {}
        )
    }
}
