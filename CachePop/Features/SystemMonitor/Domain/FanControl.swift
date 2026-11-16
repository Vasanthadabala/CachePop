import Foundation

/// Where the fan helper stands.
enum FanHelperStatus: Equatable {
    /// Not installed yet.
    case notInstalled
    /// Installed, waiting for the user to allow it in System Settings › Login Items.
    case needsApproval
    case ready
    /// Can't be used here, with the reason.
    case unavailable(String)
}


/// Installs the helper and sends it fan commands. Swapped for a fake in demo mode and tests.
@MainActor
protocol FanControlling: AnyObject {
    var status: FanHelperStatus { get }
    func install() throws
    func uninstall() async throws
    func openApprovalSettings()
    func setSpeed(fan: Int, rpm: Double) async throws
    func setAllAutomatic() async throws
    /// Called when the helper stops and starts again while CachePop is connected.
    var onHelperRestarted: () -> Void { get set }
}


struct FanControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

