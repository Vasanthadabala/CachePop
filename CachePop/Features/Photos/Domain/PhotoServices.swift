import Foundation

nonisolated protocol PhotoScanning: Sendable {
    func folders(home: URL) -> [URL]
    func scan(folders: [URL], includeLibrary: Bool, progress: @escaping @Sendable (Int, Int) -> Void) async -> PhotoScanResult
}
nonisolated protocol PhotoLibraryManaging: Sendable {
    func requestAccess() async -> Bool
    func delete(_ identifiers: [String]) async throws
}
