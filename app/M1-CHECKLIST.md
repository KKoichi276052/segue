# M1 hands-on checklist

The checks from the [M1 plan](../docs/SPEC.md#m1-plan-decided) that need someone at the MacBook: permissions, real keys, focus across Spaces and screen captures. The unit tests (`cd SegueKit && swift test`) and the build cover the rest.

Tick each box and note numbers next to it. Anything that fails goes in the step's pull request.

`B` below is the app binary:

```sh
B=/Applications/Segue.app/Contents/MacOS/Segue
```

Running `$B --some-check` from a terminal applies the *terminal's* permissions. Opening Segue.app normally applies *Segue's* own.

## 0. Set up

- [ ] Sign in to Xcode › Settings › Accounts with your Apple ID.
- [ ] `cp Local.xcconfig.example Local.xcconfig`, then set `DEVELOPMENT_TEAM`.
- [ ] Build and install:

  ```sh
  xcodegen generate
  xcodebuild -project Segue.xcodeproj -scheme Segue -configuration Release -derivedDataPath build/DerivedData build
  cp -R build/DerivedData/Build/Products/Release/Segue.app /Applications/
  ```

- [ ] `codesign -dv /Applications/Segue.app 2>&1 | grep -E "Authority|TeamIdentifier"` shows your Apple Development certificate, not `adhoc`.

## Step 1: Skeleton

- [ ] `open /Applications/Segue.app`: a menu bar icon appears, with no Dock icon.
- [ ] Grant a permission (step 2), rebuild, reinstall and reopen. The permission is still granted.

## Step 2: Permissions

- [ ] Quit Segue, then run `tccutil reset All io.github.kkoichi276052.segue` and open Segue again.
- [ ] The "Set up Segue" window appears.
- [ ] **Device Control and Data Access › Allow…**: macOS prompts. Turn Segue on, then come back.
  - [ ] The row shows "✓ Granted" within about a second.
  - [ ] Record which System Settings panes list Segue: Device Control and Data Access? Input Monitoring?
  - [ ] Record whether ⌥ Tab works without a relaunch. If it doesn't, does "Relaunch Segue" fix it?
- [ ] **Screen Recording › Allow…**, then relaunch. The row shows "✓ Granted".
- [ ] While Segue runs, turn Device Control and Data Access off in System Settings. At the next ⌥ Space, the menu bar icon shows ⚠︎ with "Needs Device Control and Data Access".

## Step 3: Private APIs

- [ ] Menu › Debug › Private API self-check shows all calls `[ok]`.
- [ ] `defaults write io.github.kkoichi276052.segue DebugDisableSkyLight -bool true`, then relaunch.
  - [ ] The menu shows the fallback note.
  - [ ] Choosing a window on another Space only activates its app.
  - [ ] Undo with `defaults delete io.github.kkoichi276052.segue DebugDisableSkyLight`.
- [ ] The same with `DebugDisableAXWindowID`. Windows are still listed and focus still works on the current Space.

## Step 4: Inventory and recency

- [ ] `$B --dump-windows` lists the same user windows as `spikes/.build/release/s1-windows` for regular apps.
  - Segue deliberately leaves out off-screen windows that are smaller than 100 pt or have an empty title (helper windows).
  - Note any real window that's missing or any helper that shows up.
- [ ] `$B --watch-windows 60`, then:
  - [ ] Open, close, rename (switch a browser tab), minimize, and move a window to another Space. Each change prints within 1 s. Moving to another Space may only show up once you switch Spaces or show the switcher.
  - [ ] At the end, CPU use is about 0%.
- [ ] Stop an app with `kill -STOP <pid>` and show the switcher. It isn't delayed by more than about 0.25 s. Then `kill -CONT <pid>`.
- [ ] Activity Monitor: Segue at 0.0% CPU over 10 idle minutes.

## Step 5: Focus

Window ids come from `$B --dump-windows`.

- [ ] `$B --focus <id>` for one window of each kind, each `[ok]`. Note the confirmation times; targets are 100 ms, and 400 ms for minimized windows.
  - [ ] on screen
  - [ ] other Space (the Space switches)
  - [ ] app hidden (⌘H)
  - [ ] minimized
- [ ] Instruments' Hangs or Time Profiler shows no main-thread hang over 16 ms while a minimized window is focused through the switcher.

## Step 6: Panel and keys

- [ ] Hold ⌥ and tap Tab quickly (under 100 ms). Segue switches to the previous window and nothing appears.
- [ ] Hold ⌥ Tab: the grid appears after about 100 ms.
  - [ ] Tab and ⇧ Tab move the selection; ◀ ▶ ▲ ▼ move it too.
  - [ ] Releasing ⌥ switches.
  - [ ] esc cancels, with no switch on release.
- [ ] ⌥ Space opens the switcher and it stays open.
  - [ ] ◀ ▶ and return switch.
  - [ ] esc closes.
  - [ ] ⌥ Space again closes.
- [ ] Over a full-screen app, both ⌥ Tab and ⌥ Space show the switcher.
- [ ] On the Dell, the switcher appears under a virtual notch when the focused window is there.
- [ ] Menu › Debug › Timing summary after 20 ⌥ Space presses and 20 holds, including the first after launch and the first after plugging in the Dell:
  - [ ] median within 16 ms;
  - [ ] first shows within 16 ms. If not, `defaults write io.github.kkoichi276052.segue KeepPanelOnScreen -bool true`, relaunch, measure again, and record idle CPU and energy (Activity Monitor › Energy) for both settings.
- [ ] During a hold, ⌥ Space keeps the switcher open (tap mode).
- [ ] With a background app opening a window (a download finishing, for example), a quick ⌥ Tab still goes to the window you used before the current one.
- [ ] Click the desktop, then quick ⌥ Tab: Segue goes to your most recent window.
- [ ] Menu › Pause Segue: ⌥ Tab and ⌥ Space reach other apps again. Unpause.
- [ ] With Segue idle, `kill -STOP $(pgrep -x Segue)`. Typing in other apps recovers within a few seconds. Then `kill -CONT $(pgrep -x Segue)`.
- [ ] kanata:
  - [ ] Menu › Debug › Log raw key events on.
  - [ ] Run `/usr/bin/log stream --info --predicate 'subsystem == "io.github.kkoichi276052.segue" AND category == "keys"'`.
  - [ ] Hold ⌥ Tab until a stray Shift appears.
  - [ ] Record what the log shows. Is there a `flagsChanged` for Shift (key 56) from kanata's virtual keyboard (`kbType`, `sourceState`)? This goes in §10 of the spec.
  - [ ] Turn the log off again.
- [ ] Notice any mistyped key or lost key in normal typing during a day of use.

## Step 7: Switcher view

- [ ] With many windows open, cards stay readable. When they don't all fit, the grid pages ("N of M shown") and the selection stays visible.
- [ ] Moving the selection feels instant. Optional: Instruments › Animation Hitches shows no frame over 16 ms.
- [ ] Japanese titles render.
- [ ] Releasing ⌥ at about 106–155 ms no longer reads as a flash. Your call; tune with `defaults write io.github.kkoichi276052.segue ShowDelayMs -int 130` if needed.
- [ ] Clicking a card focuses it; clicking outside closes.
- [ ] VoiceOver (⌘F5) announces the selected window as it moves.

## Step 8: Previews

- [ ] Images fill in after the switcher shows, the selected card first. 20 cards fill within about 1 s.
- [ ] Timing summary: show times are unchanged from step 7; capture median about 34 ms; cache within 60 MB.
- [ ] Memory with 20 or more images stays within 60 MB of the step-7 baseline (Activity Monitor › Memory, or "physical footprint" in the timing summary; idle Release build without previews: 19.6 MB).
- [ ] Nothing is captured while the switcher is hidden, apart from one capture after each switch. The ScreenCaptureKit activity indicator doesn't stay on.
- [ ] Record whether macOS 27 shows a screen-recording indicator in the menu bar during captures.
- [ ] With Screen Recording off, cards show icons and titles, and everything else works.

## Step 9: Search

- [ ] ⌥ Space, type part of a title. The bar appears under the notch and results narrow; ◀ ▶ choose; return switches.
- [ ] Hold ⌥ Tab and type a letter. The switcher stays open after ⌥ is released, and typing continues in the bar.
  - Known limitation: letters typed while ⌥ is still held skip the input method (they come through the event tap).
  - While ⌥ is still held, ◀ ▶ and return work on the results.
- [ ] Japanese IME: ⌥ Space, switch to Japanese input, type and convert a word in a Japanese window title.
  - [ ] The window is found.
  - [ ] Arrows and return work inside the conversion and only move the selection afterwards.
- [ ] Full-width input (ＡＢＣ) finds half-width titles.
- [ ] esc clears the search; esc again closes. The app that was in front is still in front and still has keyboard focus.
- [ ] While the bar has the keyboard, the frontmost app's menu bar stays (Segue didn't activate).

## Step 10: Daily use

- [ ] Menu › Launch at Login on (with Segue in /Applications), log out and in. Segue starts.
- [ ] Connect and disconnect the Dell while the switcher is open: it closes, and the next show is on the right display.
- [ ] Quit or launch an app during a hold: no crash, and the selection stays sensible.
- [ ] Switch Spaces with the trackpad while the switcher is open: it closes.
- [ ] Sleep and wake: ⌥ Tab still works.
- [ ] `defaults write io.github.kkoichi276052.segue TapHotkey "ctrl+option+space"`, then relaunch. The new key works, and the menu shows it.
- [ ] A week of daily use with Segue instead of Cmd-Tab. Note crashes, lost keys and wrong switches.
