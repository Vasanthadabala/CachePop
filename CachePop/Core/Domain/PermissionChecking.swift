import Foundation

nonisolated protocol PermissionChecking: Sendable {
    func hasFullDiskAccess() -> Bool
}
