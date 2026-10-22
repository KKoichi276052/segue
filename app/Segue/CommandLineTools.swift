import Foundation
import SegueCore
import SegueSystem

/// Arguments for checks that print and exit, so they can run from a terminal without
/// showing UI, installing an event tap or moving windows.
///
/// Run the binary directly (`Segue.app/Contents/MacOS/Segue --version`). Launched that way,
/// macOS applies the terminal's permissions, not Segue's.
enum CommandLineTools {
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        let args = Array(arguments.dropFirst())
        if args.contains("--version") {
            print("Segue \(SegueVersion.string)")
            return 0
        }
        if args.contains("--permissions") {
            print(PermissionsCoordinator.describe(PermissionsCoordinator.current()))
            return 0
        }
        if args.contains("--self-check") {
            var allOK = true
            for check in PrivateAPI.selfCheck() {
                allOK = allOK && check.ok
                print("[\(check.ok ? "ok" : "MISSING")] \(check.name): \(check.detail)")
            }
            return allOK ? 0 : 1
        }
        if args.contains("--help") {
            print("""
            Segue \(SegueVersion.string)
              --version        print the version
              --permissions    print which permissions this process has
              --self-check     check the private calls Segue uses (no side effects)
              --help           this help
            """)
            return 0
        }
        return nil
    }
}
