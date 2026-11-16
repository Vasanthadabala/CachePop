import Foundation

nonisolated struct LiveLargeFilesScanner: LargeFilesScanning {
    func defaultRoots(home: URL) -> [URL] { LargeFilesScanner.homeFolders(home: home) }
    @concurrent
    func scan(roots: [URL], threshold: Int64, progress: @escaping @Sendable (String) -> Void) async -> LargeFilesResult {
        LargeFilesScanner.scan(roots: roots, largeThreshold: threshold, progress: progress)
    }
}
