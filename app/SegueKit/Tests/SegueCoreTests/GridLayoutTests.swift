import CoreGraphics
import Testing
@testable import SegueCore

@Suite struct GridLayoutTests {
    let screen = CGSize(width: 1400, height: 820) // roughly a 14-inch MacBook's visible area, minus margins

    @Test func fewWindowsGetLargeCardsInOneRow() {
        let grid = GridLayout.compute(count: 3, available: screen)
        #expect(grid.columns == 3)
        #expect(grid.cardSize.width == 300)
        #expect(!grid.isPaged)
    }

    @Test func manyWindowsAllFitWhenTheyCan() {
        let grid = GridLayout.compute(count: 20, available: screen)
        #expect(!grid.isPaged)
        #expect(grid.columns * grid.totalRows >= 20)
        #expect(grid.size.width <= screen.width)
        #expect(grid.size.height <= screen.height)
        #expect(grid.cardSize.width >= 150)
    }

    @Test func tooManyWindowsPageByRows() {
        let grid = GridLayout.compute(count: 89, available: screen)
        #expect(grid.isPaged)
        #expect(grid.cardSize.width == 150)
        #expect(grid.size.height <= screen.height)
        #expect(grid.columns * grid.totalRows >= 89)
    }

    @Test func pagingKeepsTheSelectionVisible() {
        let grid = GridLayout.compute(count: 89, available: screen)
        for selected in [0, 44, 88] {
            let first = grid.firstVisibleRow(selected: selected)
            #expect(grid.frame(of: selected, firstRow: first) != nil)
        }
        #expect(grid.firstVisibleRow(selected: 0) == 0)
        #expect(grid.firstVisibleRow(selected: 88) == grid.totalRows - grid.visibleRows)
    }

    @Test func framesAreLaidOutRowByRow() {
        let grid = GridLayout.compute(count: 4, available: CGSize(width: 640, height: 900))
        #expect(grid.columns == 2)
        let second = grid.frame(of: 1, firstRow: 0)!
        let third = grid.frame(of: 2, firstRow: 0)!
        #expect(second.minX == grid.cardSize.width + grid.spacing)
        #expect(third.minX == 0)
        #expect(third.minY == grid.cardSize.height + grid.spacing)
    }

    @Test func zeroWindows() {
        let grid = GridLayout.compute(count: 0, available: screen)
        #expect(grid.columns == 1)
        #expect(grid.size.width > 0)
    }
}
