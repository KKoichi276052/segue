import Testing
@testable import SegueCore

@Suite struct ByteLRUTests {
    @Test func evictsLeastRecentlyUsedToFitTheBudget() {
        var cache = ByteLRU<Int, String>(capacity: 100)
        cache.insert("a", for: 1, cost: 40, at: 0)
        cache.insert("b", for: 2, cost: 40, at: 0)
        _ = cache.value(for: 1) // 1 is now more recent than 2
        cache.insert("c", for: 3, cost: 40, at: 0)
        #expect(cache.contains(1))
        #expect(!cache.contains(2))
        #expect(cache.contains(3))
        #expect(cache.totalCost == 80)
    }

    @Test func replacingAnEntryUpdatesTheCost() {
        var cache = ByteLRU<Int, String>(capacity: 100)
        cache.insert("a", for: 1, cost: 60, at: 0)
        cache.insert("a2", for: 1, cost: 30, at: 5)
        #expect(cache.totalCost == 30)
        #expect(cache.storedAt(1) == 5)
        #expect(cache.count == 1)
    }

    @Test func refusesValuesLargerThanTheBudget() {
        var cache = ByteLRU<Int, String>(capacity: 10)
        cache.insert("big", for: 1, cost: 11, at: 0)
        #expect(cache.count == 0)
        #expect(cache.totalCost == 0)
    }

    @Test func retainDropsClosedWindows() {
        var cache = ByteLRU<Int, String>(capacity: 100)
        for i in 1...4 { cache.insert("\(i)", for: i, cost: 10, at: 0) }
        cache.retain([2, 4])
        #expect(cache.count == 2)
        #expect(cache.totalCost == 20)
    }
}

@Suite struct PreviewRefreshTests {
    @Test func selectedFirstAndSkipsFreshImages() {
        let stored: [WindowID: Double] = [2: 9.5, 3: 1]
        let order = PreviewRefresh.order(visible: [1, 2, 3, 4], selected: 4, storedAt: { stored[$0] }, now: 10)
        #expect(order == [4, 1, 3])
    }

    @Test func pixelSizeKeepsShapeAndLimits() {
        #expect(PreviewRefresh.pixelSize(windowSize: (1512, 945)) == (600, 375))
        #expect(PreviewRefresh.pixelSize(windowSize: (400, 300)) == (280, 210))
        #expect(PreviewRefresh.pixelSize(windowSize: (0, 300)) == (1, 1))
    }
}
