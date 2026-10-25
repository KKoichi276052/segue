import Testing
@testable import SegueCore

@Suite struct TimingTests {
    @Test func statsOfSamples() throws {
        let stats = try #require(Stats([5, 1, 3, 2, 4]))
        #expect(stats.count == 5)
        #expect(stats.min == 1)
        #expect(stats.median == 3)
        #expect(stats.max == 5)
        #expect(stats.p95 == 5)
    }

    @Test func noSamples() {
        #expect(Stats([]) == nil)
    }
}
