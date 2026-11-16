import Foundation

// Shared by the app and CachePopFanHelper, so both sides always agree on names and calls.

nonisolated enum FanHelperConstants {
    static let label = "com.piggylabs.CachePop.FanHelper"
    static let machServiceName = label
    static let plistName = "\(label).plist"
    /// Bump when the helper changes, so the app re-registers the new one.
    static let version = "3"

    static let teamID = "4R2U97FG78"
    static let appIdentifier = "com.piggylabs.CachePop"

    /// Only CachePop signed by this team may talk to the helper.
    static let clientRequirement =
        "anchor apple generic and identifier \"\(appIdentifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    /// The app only talks to the helper signed by this team.
    static let helperRequirement =
        "anchor apple generic and identifier \"\(label)\" and certificate leaf[subject.OU] = \"\(teamID)\""

    /// Above this chip temperature, fixed fan speeds are released back to macOS.
    static let releaseTemperature: Double = 95
}

/// What the app may ask the helper to do. Every reply carries an error message, or nil.
@objc(CachePopFanHelperProtocol)
nonisolated protocol FanHelperProtocol {
    func helperVersion(reply: @escaping (String) -> Void)
    /// Holds a fan at `rpm`, clamped to the range macOS allows for it.
    func setFanSpeed(_ fan: Int, rpm: Double, reply: @escaping (String?) -> Void)
    func setAutomatic(_ fan: Int, reply: @escaping (String?) -> Void)
    func setAllAutomatic(reply: @escaping (String?) -> Void)
}
