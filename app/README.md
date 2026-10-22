# Segue app

The macOS app. The plan it follows is [§11 M1 plan](../docs/SPEC.md#m1-plan-decided); the layout is [§9 Project structure](../docs/SPEC.md#project-structure-decided).

Requires macOS 26 or later, Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd app
xcodegen generate                       # after every pull; Segue.xcodeproj is not in git
open Segue.xcodeproj                    # or build from the terminal:
xcodebuild -project Segue.xcodeproj -scheme Segue -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Segue.app

cd SegueKit && swift test               # SegueCore unit tests, headless
```

## Signing and permissions

macOS ties permissions to the app's code signature. The default build is ad-hoc signed, so its signature changes on every build and macOS forgets Segue's permissions each time. To keep them:

1. Sign in to Xcode with your Apple ID (Xcode › Settings › Accounts). A free account is enough.
2. `cp Local.xcconfig.example Local.xcconfig` and set `DEVELOPMENT_TEAM` to your team ID.
3. `xcodegen generate` and build again.

To start over with permissions: `tccutil reset All io.github.kkoichi276052.segue`.

## Checks that print and exit

Run the binary directly to print diagnostics without showing any UI. Launched from a terminal this way, macOS applies the terminal's permissions, not Segue's.

```sh
build/DerivedData/Build/Products/Debug/Segue.app/Contents/MacOS/Segue --help
```
