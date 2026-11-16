import Foundation

nonisolated struct LivePhotoScanner: PhotoScanning {
    func folders(home: URL) -> [URL] { PhotoScanner.photoFolders(home: home) }
    func scan(folders: [URL], includeLibrary: Bool, progress: @escaping @Sendable (Int, Int) -> Void) async -> PhotoScanResult {
        await PhotoScanner.scan(folders: folders, includeLibrary: includeLibrary, progress: progress)
    }
}
nonisolated struct LivePhotoLibrary: PhotoLibraryManaging {
    func requestAccess() async -> Bool { await PhotosLibraryAccess.request() }
    func delete(_ identifiers: [String]) async throws { try await PhotosLibraryAccess.delete(identifiers) }
}
