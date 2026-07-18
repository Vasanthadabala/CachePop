import Foundation

struct DuplicateFile: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let selected: Int
    let total: Int
    let thumbnail: ThumbnailKind
    let isSelected: Bool

    static let samples = [
        DuplicateFile(name: "oasis_.png", size: "1,2 GB", selected: 6, total: 7, thumbnail: .oasis, isSelected: true),
        DuplicateFile(name: "selfie_2024.zip", size: "841 MB", selected: 4, total: 5, thumbnail: .zip, isSelected: false),
        DuplicateFile(name: "wow.png", size: "21,8 MB", selected: 2, total: 3, thumbnail: .oasis, isSelected: false),
        DuplicateFile(name: "selfie_1.jpg", size: "15,3 MB", selected: 3, total: 4, thumbnail: .people, isSelected: false),
        DuplicateFile(name: "love.jpg", size: "1,6 MB", selected: 1, total: 2, thumbnail: .people, isSelected: false)
    ]
}
