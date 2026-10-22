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

## Using it

- **Hold ⌥, press Tab.** Tab and ⇧ Tab or the arrows move. Release ⌥ to switch; esc cancels. A quick ⌥ Tab switches to the previous window without showing anything.
- **⌥ Space** opens the switcher and keeps it open: type to search, ◀ ▶ to choose, return to switch, esc to clear and then close.
- **Typing a letter during a hold** starts a search and keeps the switcher open. Letters typed while ⌥ is still held skip the input method, so for Japanese, let go of ⌥ first or use ⌥ Space.
- The menu bar item shows warnings, and has Pause, Launch at Login and a Debug menu (window dump, timing summary, raw key log, private-API self-check).

## Settings

M1 has no settings window. Change these with `defaults write io.github.kkoichi276052.segue <key> <value>`, then relaunch.

| Key | Type | Default | What it does |
|---|---|---|---|
| `TapHotkey` | string | `option+space` | The key that opens the switcher and keeps it open, for example `ctrl+option+space` |
| `ShowDelayMs` | int | `100` | How long ⌥ Tab is held before the switcher shows (0–250) |
| `KeepPanelOnScreen` | bool | `false` | Keep the panel on screen but transparent while hidden |
| `DebugKeyLog` | bool | `false` | Log raw modifier and navigation key events (never typed text) |
| `DebugDisableSkyLight`, `DebugDisableAXWindowID` | bool | `false` | Pretend a private call is missing, to exercise its fallback |

## Logs

```sh
/usr/bin/log stream --info --predicate 'subsystem == "io.github.kkoichi276052.segue"'
```

In zsh, `log` is a shell builtin, so use the full path.

## Checks that print and exit

Run the binary directly to print diagnostics without showing any UI. Launched from a terminal this way, macOS applies the terminal's permissions, not Segue's.

```sh
B=build/DerivedData/Build/Products/Debug/Segue.app/Contents/MacOS/Segue
$B --help                 # all options
$B --dump-windows         # the window list and how long it took to build
$B --watch-windows 60     # live changes for 60 s, then CPU use
$B --self-check           # the private calls
$B --focus <id>           # focus one window and time it (moves focus)
$B --render-preview /tmp/s.png --sample 40 --query doc   # draw the switcher offscreen
$B --no-input             # run without the hotkey and the event tap
```

The hands-on checks for M1 are in [M1-CHECKLIST.md](M1-CHECKLIST.md).
