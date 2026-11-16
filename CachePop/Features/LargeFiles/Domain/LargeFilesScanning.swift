import Foundation

nonisolated enum LargeFilePolicy {
    static let defaultThreshold: Int64 = 100 * 1_048_576
}
nonisolated protocol LargeFilesScanning: Sendable {
    func defaultRoots(home: URL) -> [URL]
    func scan(roots: [URL], threshold: Int64, progress: @escaping @Sendable (String) -> Void) async -> LargeFilesResult
}

nonisolated protocol FileClassifying: Sendable {
    func kind(of url: URL) -> FileKind
}

@MainActor
protocol LargeFilePreferencesProviding {
    var largeFileFolders: [String] { get }
    var largeFileThreshold: Int64 { get }
}
