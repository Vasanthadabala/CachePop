import Foundation
import Testing
@testable import CachePop

@Suite("Breakdown bar layout")
struct BreakdownGeometryTests {
    @Test func tinyCategoriesStayVisibleWithoutOverflow() {
        let widths = BreakdownGeometry.widths(for: [1_000_000, 1, 1, 1], availableWidth: 200)
        #expect(widths.count == 4)
        #expect(widths.allSatisfy { $0 >= 6 })
        #expect(abs(widths.reduce(0, +) + 9 - 200) < 0.001)
        #expect(widths[0] > widths[1])
    }

    @Test func narrowBarsFitWithoutNegativeWidths() {
        let widths = BreakdownGeometry.widths(for: [100, 1, 1, 1, 1], availableWidth: 24)
        #expect(widths.allSatisfy { $0 >= 0 })
        #expect(abs(widths.reduce(0, +) + 12 - 24) < 0.001)
    }

    @Test func emptyAndZeroTotalsStayFinite() {
        #expect(BreakdownGeometry.widths(for: [], availableWidth: 200).isEmpty)
        let widths = BreakdownGeometry.widths(for: [0, 0], availableWidth: 100)
        #expect(widths.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(abs(widths.reduce(0, +) + 3 - 100) < 0.001)
    }
}
