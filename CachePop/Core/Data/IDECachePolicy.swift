import Foundation

/// IntelliJ-based IDEs put recovery history beside their disposable indexes.
nonisolated enum IDECachePolicy {
    struct Product: Sendable {
        let folderPrefix: String
        let bundleID: String
        let name: String
    }

    static let products: [Product] = [
        Product(folderPrefix: "intellijidea", bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        Product(folderPrefix: "ideaic", bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        Product(folderPrefix: "ideaiu", bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        Product(folderPrefix: "pycharm", bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        Product(folderPrefix: "pycharmce", bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        Product(folderPrefix: "webstorm", bundleID: "com.jetbrains.webstorm", name: "WebStorm"),
        Product(folderPrefix: "phpstorm", bundleID: "com.jetbrains.phpstorm", name: "PhpStorm"),
        Product(folderPrefix: "clion", bundleID: "com.jetbrains.clion", name: "CLion"),
        Product(folderPrefix: "goland", bundleID: "com.jetbrains.goland", name: "GoLand"),
        Product(folderPrefix: "rider", bundleID: "com.jetbrains.rider", name: "Rider"),
        Product(folderPrefix: "datagrip", bundleID: "com.jetbrains.datagrip", name: "DataGrip"),
        Product(folderPrefix: "rubymine", bundleID: "com.jetbrains.rubymine", name: "RubyMine"),
        Product(folderPrefix: "rustrover", bundleID: "com.jetbrains.rustrover", name: "RustRover")
    ]

    static func product(for folder: String) -> Product? {
        let name = folder.lowercased()
        return products.first {
            name.range(of: "^\($0.folderPrefix)[0-9]+(?:\\.[0-9]+)*(?:eap)?$", options: .regularExpression) != nil
        }
    }

    static func displayName(for bundleID: String) -> String? {
        bundleID == "com.google.android.studio" ? "Android Studio" : products.first { $0.bundleID == bundleID }?.name
    }
}
