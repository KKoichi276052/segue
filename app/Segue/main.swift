import AppKit
import SegueCore

// Entry point. Debug arguments print and exit (see CommandLineTools.swift); otherwise
// Segue runs as a menu-bar-only app.

if let code = CommandLineTools.runIfRequested(CommandLine.arguments) {
    exit(code)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
