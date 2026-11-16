import Darwin
import Foundation

nonisolated extension FileReviewIdentity {
    static func read(_ url: URL) -> FileReviewIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileReviewIdentity(storage: Storage(device: Int64(info.st_dev), inode: UInt64(info.st_ino)),
                                  bytes: Int64(info.st_size),
                                  modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                                  modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                                  changedSeconds: Int64(info.st_ctimespec.tv_sec),
                                  changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    func matches(_ url: URL) -> Bool { Self.read(url) == self }
}
