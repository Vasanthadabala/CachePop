import Foundation
import SwiftData

/// One finished clean, as shown in History.
@Model
final class CleanRecord {
    var date: Date
    /// Space the clean freed, measured from the disk (or estimated when it couldn't be read).
    var freedBytes: Int64
    var wasMeasured: Bool
    var itemCount: Int
    var trashBytes: Int64
    /// Titles of what was cleaned, largest first.
    var titles: [String]

    init(date: Date, freedBytes: Int64, wasMeasured: Bool, itemCount: Int, trashBytes: Int64, titles: [String]) {
        self.date = date
        self.freedBytes = freedBytes
        self.wasMeasured = wasMeasured
        self.itemCount = itemCount
        self.trashBytes = trashBytes
        self.titles = titles
    }
}
