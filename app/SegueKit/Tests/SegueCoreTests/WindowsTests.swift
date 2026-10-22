import CoreGraphics
import Testing
@testable import SegueCore

@Suite struct WindowMergerTests {
    let apps = [AppRecord(pid: 1, name: "Safari", bundleID: "com.apple.Safari"),
                AppRecord(pid: 2, name: "Zed", bundleID: "dev.zed.Zed"),
                AppRecord(pid: 3, name: "Notes", bundleID: "com.apple.Notes", isHidden: true)]
    let big = CGRect(x: 0, y: 0, width: 800, height: 600)

    func server(_ id: WindowID, pid: Int32, title: String? = nil, onScreen: Bool = true, bounds: CGRect? = nil) -> ServerWindow {
        ServerWindow(id: id, pid: pid, ownerName: "", title: title, bounds: bounds ?? big, isOnScreen: onScreen)
    }

    @Test func matchesByWindowIDAndPrefersAccessibilityTitles() {
        let result = WindowMerger.merge(
            server: [server(10, pid: 1, title: "server title")],
            ax: [AXWindowRecord(windowID: 10, pid: 1, title: "AX title", frame: big, isMinimized: false)],
            apps: apps, axReadPIDs: [1], ownPID: 99)
        #expect(result.windows.map(\.title) == ["AX title"])
        #expect(result.windows.first?.hasAccessibilityElement == true)
        #expect(result.axIndex == [10: 0])
    }

    @Test func keepsOtherSpaceWindowsWithoutAccessibility() {
        let result = WindowMerger.merge(
            server: [server(20, pid: 2, title: nil, onScreen: false)],
            ax: [], apps: apps, axReadPIDs: [2], rememberedTitles: [20: "main.rs"], ownPID: 99)
        #expect(result.windows.count == 1)
        #expect(result.windows[0].title == "main.rs")
        #expect(result.windows[0].kind == .otherSpace)
    }

    @Test func dropsHelpersAndNonUserWindows() {
        let result = WindowMerger.merge(
            server: [
                server(1, pid: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 90)), // too small
                server(2, pid: 1),                                                    // palette
                server(3, pid: 1),                                                    // on screen, no AX match
                server(4, pid: 2, title: "", onScreen: false),                        // untitled, off screen
                server(5, pid: 42),                                                   // not a regular app
                server(6, pid: 99),                                                   // Segue itself
                ServerWindow(id: 7, pid: 1, ownerName: "", title: nil, bounds: big, isOnScreen: true, layer: 25),
                ServerWindow(id: 8, pid: 1, ownerName: "", title: nil, bounds: big, isOnScreen: true, alpha: 0),
            ],
            ax: [AXWindowRecord(windowID: 2, pid: 1, title: "Colors", frame: big, isMinimized: false, subrole: "AXFloatingWindow")],
            apps: apps + [AppRecord(pid: 99, name: "Segue", bundleID: nil)], axReadPIDs: [1, 2], ownPID: 99)
        #expect(result.windows.isEmpty)
    }

    @Test func keepsOnScreenWindowsOfAppsAccessibilityCouldNotRead() {
        let result = WindowMerger.merge(server: [server(3, pid: 1, title: "x")], ax: [], apps: apps, axReadPIDs: [], ownPID: 99)
        #expect(result.windows.count == 1)
    }

    @Test func fallsBackToFrameAndTitleWithoutWindowIDs() {
        let left = CGRect(x: 0, y: 0, width: 600, height: 600)
        let right = CGRect(x: 600, y: 0, width: 600, height: 600)
        let result = WindowMerger.merge(
            server: [server(1, pid: 1, title: "B", bounds: right), server(2, pid: 1, title: "A", bounds: left)],
            ax: [AXWindowRecord(windowID: nil, pid: 1, title: "A", frame: left, isMinimized: false),
                 AXWindowRecord(windowID: nil, pid: 1, title: "B", frame: right, isMinimized: true)],
            apps: apps, axReadPIDs: [1], ownPID: 99)
        #expect(result.windows.map(\.id) == [1, 2])
        #expect(result.axIndex == [1: 1, 2: 0])
        #expect(result.windows[0].kind == .minimized)
    }

    @Test func kinds() {
        let result = WindowMerger.merge(
            server: [server(1, pid: 3, title: "Shopping", onScreen: false)],
            ax: [], apps: apps, axReadPIDs: [3], ownPID: 99)
        #expect(result.windows.first?.kind == .appHidden)
    }
}

@Suite struct RecencyListTests {
    @Test func syncSeedsInGivenOrderAndKeepsKnownOrder() {
        var list = RecencyList()
        list.sync([3, 1, 2])
        #expect(list.order == [3, 1, 2])
        list.touch(2)
        list.sync([1, 2, 3, 4])
        #expect(list.order == [2, 3, 1, 4])
    }

    @Test func syncDropsClosedWindows() {
        var list = RecencyList(order: [1, 2, 3])
        list.sync([3, 1])
        #expect(list.order == [1, 3])
    }

    @Test func touchMovesToFrontAndAddsUnknown() {
        var list = RecencyList(order: [1, 2, 3])
        list.touch(3)
        #expect(list.order == [3, 1, 2])
        list.touch(9)
        #expect(list.order == [9, 3, 1, 2])
    }

    @Test func sortedUsesRecencyThenInputOrder() {
        let list = RecencyList(order: [2, 1])
        func w(_ id: WindowID) -> WindowInfo {
            WindowInfo(id: id, pid: 1, appName: "", bundleID: nil, title: "", frame: .zero, isMinimized: false,
                       isAppHidden: false, isOnScreen: true, hasAccessibilityElement: true)
        }
        #expect(list.sorted([w(1), w(3), w(2), w(4)]).map(\.id) == [2, 1, 3, 4])
    }
}
