import Foundation

nonisolated struct LiveLoginItemsListing: LoginItemsListing {
    let home: URL

    @concurrent
    func agents(overrides: LaunchOverrides) async -> [LoginItem] {
        let liveHome = home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return LoginItemsScanner.agents(home: home, overrides: overrides, includeSystemItems: liveHome)
    }

    @concurrent
    func apps(
        _ openAtLogin: [OpenAtLoginApp], remembering remembered: [String]
    ) async -> LoginAppListing {
        let listed = Set(openAtLogin.map(\.path))
        let retained = remembered.filter {
            !Task.isCancelled && !listed.contains($0) && FileManager.default.fileExists(atPath: $0)
        }
        let items = openAtLogin.map {
            LoginItem(title: ApplicationDetails.cleanName($0.name) ?? $0.name, path: $0.path, kind: .openAtLogin, appPath: $0.path)
        } + retained.map {
            LoginItem(title: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent,
                      path: $0, kind: .openAtLogin, appPath: $0, isOn: false)
        }
        return LoginAppListing(items: items, remembered: retained)
    }

}
