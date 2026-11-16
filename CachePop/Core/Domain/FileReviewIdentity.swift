import Foundation

nonisolated struct FileReviewIdentity: Sendable, Hashable {
    struct Storage: Sendable, Hashable {
        let device: Int64
        let inode: UInt64
    }

    let storage: Storage
    let bytes: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

}
