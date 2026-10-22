# M0 spikes

Swift executables that answer the technical questions in [§10 of the spec](../docs/SPEC.md#10-technical-risks-and-spikes). Each one prints its measurements and a pass or fail against the spec's targets. They move, focus and capture real windows, but write nothing to disk and use no network.

Requires macOS 14 or later and Swift 6 (Xcode or Command Line Tools).

```sh
cd spikes
swift build -c release
.build/release/s1-windows
```

## Permissions

macOS grants permissions to the app that launches the process: your terminal, not the spike binary. Grant them in System Settings › Privacy & Security, then quit and reopen the terminal.

| Spike | Needs |
|---|---|
| `s1-windows` | Accessibility (without it, only the Window Server list is timed). Screen Recording adds window titles to the list. |
| `s2-arrange` | Accessibility |
| `s4-capture` | Screen Recording; Accessibility to tell minimized windows from other-Space ones |
| `s6-panel` | Accessibility and/or Input Monitoring for the event tap. Finding out which is part of the spike. |

## Running each spike

**S1 Window list.** Open 20 or more windows across several apps, minimize one, and put a few on another Space.

```sh
.build/release/s1-windows               # list and time
.build/release/s1-windows --focus <id>  # focus one window (ids are in the list)
.build/release/s1-windows --focus-all   # focus every window in turn
```

**S2 Arranging.** Open one window each in at least three of Safari, Chrome, VS Code, Xcode, Terminal and Finder, on the current Space. Watch the screen for bounce while it runs. Windows go back to where they were at the end.

```sh
.build/release/s2-arrange
.build/release/s2-arrange --apps com.apple.Safari,com.apple.Terminal,com.apple.finder
.build/release/s2-arrange --keep-enhanced-ui   # compare with AXEnhancedUserInterface left on
```

**S4 Window images.** Have some windows minimized, one app hidden (⌘H) and some windows on another Space.

```sh
.build/release/s4-capture
.build/release/s4-capture --pixel-scale 1.4   # preview size at Retina density, for comparison
```

**S6 Panel and keys.** Runs until ctrl-C, then prints a summary. Press ⌥ Space several times on each display and over a full-screen app. Hold ⌥ and press Tab, both quickly (under 100 ms) and slowly. Run it once with no event permissions to see what macOS asks for, then again after granting.

```sh
.build/release/s6-panel
.build/release/s6-panel --listen-only   # compare which permission a listen-only tap needs
```

## Recording results

Paste each summary block into the spike results table in [§10 of the spec](../docs/SPEC.md#m0-spike-plan-proposed), with the macOS version and Mac model it prints.

## Notes on method

- **S1** matches Accessibility windows to window IDs with the private `_AXUIElementGetWindow`, as AltTab does. Accessibility only returns windows on the current Space, so windows on other Spaces show as "no AX match". That is a finding, not a bug in the spike. To focus those windows it uses AltTab's private calls (`SpikeKit/Focus.swift`): it looks for the AX element by remote token, then brings the window forward with SkyLight's `_SLPSSetFrontProcessWithOptions`, which also switches Space. SkyLight is loaded with `dlopen`, not linked.
- **S2** sets size, then position, then size again, and turns off `AXEnhancedUserInterface` while it does, as Rectangle does. It counts "bounce" as the frame changing in the 300 ms after it was set. A window that ends at the right position, but at the app's minimum size or slightly smaller because the app sizes in steps (Terminal's character cells), counts as placed: that's as close as any window manager can get. Exact landings are reported alongside.
- **S4** treats a capture that comes back all black as blank, which is how failed captures of off-screen windows usually look. Its Strategies section also times capturing every window at once and keeping an `SCStream` per window. Those are printed for comparison, not judged against the target.
- **S6** times from the key event's timestamp to the target time of the first display frame after the panel is committed. That estimates when the panel is on screen; it doesn't observe the pixels. Hold mode is timed from the end of its show delay.
