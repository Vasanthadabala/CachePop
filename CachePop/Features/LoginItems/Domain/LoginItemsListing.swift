import Foundation

nonisolated struct LoginAppListing: Sendable {
    let items: [LoginItem]
    let remembered: [String]
}
nonisolated protocol LoginItemsListing: Sendable {
    func agents(overrides: LaunchOverrides) async -> [LoginItem]
    func apps(_ openAtLogin: [OpenAtLoginApp], remembering paths: [String]) async -> LoginAppListing
}
