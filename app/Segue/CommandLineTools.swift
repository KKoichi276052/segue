import Foundation
import SegueCore

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
        if args.contains("--help") {
            print("""
            Segue \(SegueVersion.string)
              --version        print the version
              --help           this help
            """)
            return 0
        }
        return nil
    }
}
