import Foundation
import Darwin

/// Small configuration files must not allocate buffers proportional to an unexpected file size.
nonisolated enum MetadataReader {
    static let maximumBytes = 1_048_576

    static func data(from url: URL, limit: Int = maximumBytes) -> Data? {
        guard !Task.isCancelled, limit > 0, limit < Int.max else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else {
            close(descriptor)
            return nil
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit,
              !Task.isCancelled else { return nil }
        return data
    }

    static func propertyList(from url: URL) -> [String: Any]? {
        guard let data = data(from: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}
