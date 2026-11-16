import Foundation

@MainActor
protocol SettingsStoring {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
}

enum AppLoginStatus { case disabled, enabled, needsApproval }
@MainActor
protocol AppLoginControlling {
    var status: AppLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}
