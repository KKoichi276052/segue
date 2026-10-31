import Testing
@testable import SegueCore

struct SpaceRouteTests {
    let displays = [
        SpaceRoute.Display(id: "built-in", current: 1201, spaces: [6, 1201, 1010]),
        SpaceRoute.Display(id: "external", current: 1271, spaces: [1271, 1300]),
    ]

    @Test func movesLeftToAnEarlierSpace() {
        #expect(SpaceRoute.compute(windowSpaces: [6], displays: displays) == SpaceRoute(display: "built-in", target: 6, steps: -1))
    }

    @Test func movesRightToALaterSpace() {
        #expect(SpaceRoute.compute(windowSpaces: [1010], displays: displays)?.steps == 1)
    }

    @Test func otherDisplaysCountFromTheirOwnCurrentSpace() {
        #expect(SpaceRoute.compute(windowSpaces: [1300], displays: displays) == SpaceRoute(display: "external", target: 1300, steps: 1))
    }

    @Test func noMoveWhenAlreadyShowing() {
        #expect(SpaceRoute.compute(windowSpaces: [1201], displays: displays) == nil)
        #expect(SpaceRoute.compute(windowSpaces: [1271], displays: displays) == nil)
        // On every Space (or on a showing one among several).
        #expect(SpaceRoute.compute(windowSpaces: [6, 1201], displays: displays) == nil)
    }

    @Test func unknownSpacesGiveNoRoute() {
        #expect(SpaceRoute.compute(windowSpaces: [], displays: displays) == nil)
        #expect(SpaceRoute.compute(windowSpaces: [999], displays: displays) == nil)
        #expect(SpaceRoute.compute(windowSpaces: [6], displays: []) == nil)
    }
}
