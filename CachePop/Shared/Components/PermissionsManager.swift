import Foundation
import Observation

@Observable
@MainActor
final class PermissionsManager {
    private let checker: any PermissionChecking
    private let desktop: any DesktopInteracting
    private(set) var hasFullDiskAccess = false
    init(checker: any PermissionChecking, desktop: any DesktopInteracting) {
        self.checker = checker
        self.desktop = desktop
        refresh()
    }
    func refresh() { hasFullDiskAccess = checker.hasFullDiskAccess() }
    func requestFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        desktop.open(url)
    }
}
