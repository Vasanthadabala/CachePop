import Foundation
import Synchronization
import UniformTypeIdentifiers

nonisolated extension FileKind {
    static let diskImageExtensions: Set<String> = [
        "dmg", "iso", "img", "pkg", "mpkg", "ipsw", "sparseimage", "xip", "vmdk", "qcow2", "vdi", "raw", "toast"
    ]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz4"]

    /// Kinds by extension. The `UTType` lookup is slow, and the filters and counts in the list
    /// ask again for every file on every redraw.
    private static let kindsByExtension = Mutex<[String: FileKind]>([:])
    static let maximumCachedExtensions = 512
    static var cachedExtensionCount: Int { kindsByExtension.withLock { $0.count } }

    static func clearCache() { kindsByExtension.withLock { $0.removeAll(keepingCapacity: false) } }

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if let known = kindsByExtension.withLock({ $0[ext] }) { return known }
        let kind = of(extension: ext)
        kindsByExtension.withLock {
            if $0.count >= maximumCachedExtensions { $0.removeAll(keepingCapacity: true) }
            $0[ext] = kind
        }
        return kind
    }

    private static func of(extension ext: String) -> FileKind {
        if diskImageExtensions.contains(ext) { return .diskImages }
        if archiveExtensions.contains(ext) { return .archives }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .diskImage) { return .diskImages }
        return .other
    }
}

nonisolated struct SystemFileClassifier: FileClassifying {
    func kind(of url: URL) -> FileKind { FileKind.of(url) }
}
