import Foundation
import ServiceManagement

struct UserDefaultsSettingsStore: SettingsStoring {
    let defaults: UserDefaults
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }
    func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
}
struct SystemAppLoginController: AppLoginControlling {
    var status: AppLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .disabled
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
