import AppKit
import SegueCore
import SegueSystem
import SegueUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        Log.app.info("Segue \(SegueVersion.string, privacy: .public) launched")
    }
}
