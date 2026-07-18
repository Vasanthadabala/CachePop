import Foundation
import UniformTypeIdentifiers

struct ClutterScanResult {
    let largeFiles: [CareScanDetailItem]
    let duplicates: [CareScanDetailItem]
    let duplicateGroups: [ClutterDuplicateGroup]
    let permissions: [String]

    static let empty = ClutterScanResult(details: [], permissions: [])

    init(details: [CareScanDetailItem], permissions: [String]) {
        self.largeFiles = details
            .filter { $0.kind == "Large File" }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        let duplicateItems = details
            .filter { $0.kind == "Duplicate Candidate" }
            .sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
        self.duplicateGroups = Dictionary(grouping: duplicateItems) { item in
            item.detail.hasPrefix("duplicate-group-") ? item.detail : "\(item.sizeBytes)-\(item.title)"
        }
        .values
        .map { items in
            let sortedItems = items.sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
            return ClutterDuplicateGroup(items: sortedItems)
        }
        .sorted { $0.totalBytes > $1.totalBytes }
        self.duplicates = duplicateGroups.compactMap(\.representative)
        self.permissions = permissions
    }

    var duplicateCountByRepresentativeID: [String: Int] {
        Dictionary(uniqueKeysWithValues: duplicateGroups.compactMap { group in
            guard let representative = group.representative else { return nil }
            return (representative.id, group.items.count)
        })
    }

    var selectedCount: Int {
        largeFiles.count + duplicates.count
    }

    var selectedSize: String {
        let bytes = (largeFiles + duplicates).reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var filesToSortCount: Int {
        largeFiles.count + duplicateGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicatePhotoFileCount: Int {
        duplicatePhotoGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicateOtherFileCount: Int {
        duplicateOtherGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicatePhotoSizeText: String {
        formattedDuplicateSize(for: duplicatePhotoGroups)
    }

    var duplicateOtherSizeText: String {
        formattedDuplicateSize(for: duplicateOtherGroups)
    }

    var largeFilesSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: largeFiles.reduce(Int64(0)) { $0 + $1.sizeBytes },
            countStyle: .file
        )
    }

    var duplicatePhotoPreviewItems: [CareScanDetailItem] {
        duplicatePhotoGroups.flatMap(\.items)
    }

    private var duplicatePhotoGroups: [ClutterDuplicateGroup] {
        duplicateGroups.filter { group in
            guard let representative = group.representative else { return false }
            return Self.isImagePath(representative.path)
        }
    }

    private var duplicateOtherGroups: [ClutterDuplicateGroup] {
        duplicateGroups.filter { group in
            guard let representative = group.representative else { return true }
            return !Self.isImagePath(representative.path)
        }
    }

    private func formattedDuplicateSize(for groups: [ClutterDuplicateGroup]) -> String {
        let bytes = groups.reduce(Int64(0)) { total, group in
            total + group.items.dropFirst().reduce(Int64(0)) { $0 + $1.sizeBytes }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func isImagePath(_ path: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image)
    }

    func filtered(for target: ClutterReviewTarget) -> ClutterScanResult {
        switch target {
        case .all:
            return self
        case .largeFiles:
            return ClutterScanResult(details: largeFiles, permissions: permissions)
        case .duplicatePhotos:
            return ClutterScanResult(details: duplicatePhotoGroups.flatMap(\.items), permissions: permissions)
        case .duplicateOtherFiles:
            return ClutterScanResult(details: duplicateOtherGroups.flatMap(\.items), permissions: permissions)
        }
    }

    func items(for section: ClutterSection) -> [CareScanDetailItem] {
        switch section {
        case .largeFiles:
            largeFiles
        case .duplicates:
            duplicates
        }
    }

    func relatedItems(for item: CareScanDetailItem, in section: ClutterSection) -> [CareScanDetailItem] {
        guard section == .duplicates else { return [item] }
        return duplicateGroups.first { $0.representative?.id == item.id }?.items ?? [item]
    }
}

struct ClutterDuplicateGroup {
    let items: [CareScanDetailItem]

    var representative: CareScanDetailItem? {
        items.first
    }

    var totalBytes: Int64 {
        items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }
}
