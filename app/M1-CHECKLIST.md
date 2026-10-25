# M1 hands-on checklist

These are the checks from the [M1 plan](../docs/SPEC.md#m1-plan-decided) that need someone at the MacBook: permissions, real key presses, focus across Spaces, and screen captures. The unit tests (`cd SegueKit && swift test`) and the agent's command-line checks cover the rest ([M1 findings](../docs/SPEC.md#m1-findings)).

**Time.** Sections 0–5 take about an hour. Sections 6–10 take another hour or so, plus a week of daily use. You can stop between sections; nothing depends on doing it all in one sitting.

**Recording results.** Tick each box (`- [x]`) and write numbers or notes after it, like `- [x] … — 12.4 ms`. If something fails, write what you did and what happened instead. When you're done, or part way through, tell Claude; the results go into §10 of the spec. A summary table to fill in is at the [end](#results).

## Before you start

### Where to run the commands

The M1 code is on the `m1/app` branch until PR #6 is merged into `development`. Use either checkout:

- **Before #6 is merged:** the worktree Claude used, `~/.t3/worktrees/segue/m1-app`. (Git won't check out `m1/app` in a second place while that worktree exists.)
- **After #6 is merged:** your main checkout, on `development`:

  ```sh
  cd ~/codespaces/segue && git fetch && git switch development && git pull
  ```

Every command below runs from the `app/` folder of that checkout, unless it says otherwise. Set these once in each terminal you use:

```sh
cd ~/.t3/worktrees/segue/m1-app/app        # or ~/codespaces/segue/app
B=/Applications/Segue.app/Contents/MacOS/Segue
ID=io.github.kkoichi276052.segue
```

### Two ways to run Segue

- `open /Applications/Segue.app` runs Segue normally, with **Segue's own** permissions. Use this for everything about keys, the switcher and permissions.
- `$B --some-check` runs one check from the terminal and exits. macOS applies the **terminal's** permissions, so the terminal needs Device Control and Data Access (and Screen Recording, for titles of windows on other Spaces). These checks never show the switcher or install the event tap.

### If the keyboard misbehaves

Segue's event tap sees every key while it runs. If typing ever goes wrong:

1. Menu bar icon › **Pause Segue**. Segue lets go of all keys at once.
2. If you can't reach the menu: `pkill -x Segue` in a terminal, or Activity Monitor › Segue › Quit.

macOS also turns off a tap that stops responding, so the keyboard comes back on its own within a few seconds.

### Your setup, for these checks

- **Use the left ⌥ key** for every ⌥ Tab and ⌥ Space below. Your right ⌥ is mapped to ⌃ Space (input method toggle).
- **kanata** turns Space into Shift when it's held for 150 ms or more. That's why step 6 has a check for stray Shift presses.
- **Logs.** To watch what Segue logs while you test, keep a second terminal running this. In zsh, `log` is a built-in command, so use the full path:

  ```sh
  /usr/bin/log stream --info --predicate 'subsystem == "io.github.kkoichi276052.segue"'
  ```

## 0. Set up signing and install

**Why:** macOS ties permissions to the app's code signature. The default build is ad-hoc signed, so its signature changes on every build and macOS forgets Segue's permissions each time. A free Apple Development certificate keeps the signature stable.

1. - [ ] **Sign in to Xcode.** Xcode › Settings › Accounts › **+** › Apple ID. A free account is enough; it shows up as a team called "*Your Name* (Personal Team)".
2. - [ ] **Create the certificate.** In the same pane, select your Apple ID › Manage Certificates… › **+** › Apple Development. Skip this if one is already listed.
3. - [ ] **Find your team ID.** It's the `OU=` value, 10 characters:

   ```sh
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```

4. - [ ] **Set it in `Local.xcconfig`.** This file isn't in git.

   ```sh
   cp Local.xcconfig.example Local.xcconfig
   open -e Local.xcconfig        # replace YOURTEAMID with the OU value, then save
   ```

5. - [ ] **Build a Release build.** XcodeGen needs to run after every pull, because the Xcode project isn't in git:

   ```sh
   xcodegen generate
   xcodebuild -project Segue.xcodeproj -scheme Segue -configuration Release \
     -derivedDataPath build/DerivedData -allowProvisioningUpdates build
   ```

   The last line should be `** BUILD SUCCEEDED **`.

6. - [ ] **Install it in /Applications.** Remove the old copy first, so no stale files stay behind:

   ```sh
   pkill -x Segue; sleep 1
   rm -rf /Applications/Segue.app
   ditto build/DerivedData/Build/Products/Release/Segue.app /Applications/Segue.app
   ```

7. - [ ] **Check the signature.** This should name your Apple Development certificate and team ID, not `adhoc`:

   ```sh
   codesign -dv /Applications/Segue.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
   ```

To update Segue later, repeat steps 5 and 6. Permissions survive as long as step 7 still shows the same certificate.

## 1. Skeleton

**Why:** confirms Segue runs as a menu bar app and keeps its permissions across rebuilds.

- [ ] `open /Applications/Segue.app`. An icon (two overlapping rectangles) appears in the menu bar. There's no Dock icon, and Segue isn't listed in ⌘ Tab.
- [ ] Click the icon. The first line shows the version, `Segue 0.1.0`.
- [ ] Do this one after step 2: rebuild and reinstall (section 0, steps 5–6), then open Segue again. The Set up Segue window doesn't open, the menu has no ⚠︎ warning and no **Permissions…** item (it only appears while something is missing), and ⌥ Tab works.

## 2. Permissions

**Why:** the first-launch window has to get Segue from nothing to fully working without a terminal. macOS 27 renamed the Accessibility pane, and we don't yet know exactly which panes list Segue.

1. - [ ] **Start from nothing.**

   ```sh
   pkill -x Segue; tccutil reset All $ID
   open /Applications/Segue.app
   ```

2. - [ ] The **Set up Segue** window appears: "Segue needs one permission, and one more is recommended." Both rows say "Not granted".
3. **Device Control and Data Access (required).**
   - [ ] Click **Allow…**. macOS shows its own prompt. Follow it to System Settings and turn Segue on.
   - [ ] Come back to the Set up Segue window. Within about a second, the row says **✓ Granted** without you doing anything.
   - [ ] Without relaunching, hold ⌥ and press Tab twice, then release. Does the switcher appear? If not, click **Relaunch Segue** and try again. Record which one it took: ________
   - [ ] Open System Settings › Privacy & Security and record each pane that lists Segue: Device Control and Data Access? Input Monitoring? Accessibility (if it exists)? ________
4. **Screen Recording (optional).**
   - [ ] Click **Allow…**, turn Segue on in System Settings (the pane may be called Screen & System Audio Recording), then click **Relaunch Segue**. macOS only applies Screen Recording when an app starts.
   - [ ] After the relaunch, the Set up Segue window doesn't come back, and the menu no longer has a **Permissions…** item. Both mean everything is granted.
5. **Revoking.**
   - [ ] With Segue running, turn Segue **off** under Device Control and Data Access.
   - [ ] Press ⌥ Space once. The menu bar icon becomes a ⚠︎ triangle, and the menu says "⚠︎ Needs Device Control and Data Access to switch windows".
   - [ ] Turn it back on. The next time you open the menu or show the switcher, the warning is gone.

## 3. Private APIs

**Why:** Segue uses two private macOS calls (SkyLight focus and `_AXUIElementGetWindow`). If a macOS update removes one, Segue should fall back instead of breaking. These defaults pretend each call is missing.

- [ ] Menu › Debug › **Private API self-check**. Every line starts with `[ok]`.
- **Without SkyLight:**
  - [ ] Turn it off and relaunch:

    ```sh
    defaults write $ID DebugDisableSkyLight -bool true
    pkill -x Segue; open /Applications/Segue.app
    ```

  - [ ] The menu shows "Windows on other Spaces open their app only (private call unavailable)".
  - [ ] ⌥ Tab to a window on the **same** Space. It's focused.
  - [ ] ⌥ Tab to a window on **another** Space. Expected: only its app comes forward, maybe with a different window, and the Space may not switch. Record what happened: ________
  - [ ] Undo it and relaunch:

    ```sh
    defaults delete $ID DebugDisableSkyLight
    pkill -x Segue; open /Applications/Segue.app
    ```

- **Without `_AXUIElementGetWindow`:**
  - [ ] The same with `DebugDisableAXWindowID`, then relaunch.
  - [ ] The menu shows "Window matching uses app, title and frame (private call unavailable)".
  - [ ] Menu › Debug › Dump windows still lists your windows, and ⌥ Tab still focuses windows on the current Space.
  - [ ] Undo it with `defaults delete $ID DebugDisableAXWindowID` and relaunch.

## 4. Window list and recent order

**Why:** the window list is kept up to date in the background, so that showing the switcher never has to build it. It has to match what's really open, notice changes quickly, and cost nothing when nothing changes.

These checks run from the terminal, so the terminal needs Device Control and Data Access and Screen Recording.

1. **Compare with the M0 spike.**
   - [ ] Build the spike once, from the repository root (not `app/`):

     ```sh
     (cd ../spikes && swift build -c release)
     ```

   - [ ] List windows both ways:

     ```sh
     $B --dump-windows > /tmp/segue.txt
     ../spikes/.build/release/s1-windows > /tmp/s1.txt
     open -e /tmp/segue.txt /tmp/s1.txt
     ```

   - [ ] Every real window (one you'd want to switch to) in `s1.txt` is also in `segue.txt`. Segue deliberately leaves out off-screen windows that are smaller than 100 pt or have no title. Record any real window that's missing, or any helper window that shows up: ________
2. **Live changes.**
   - [ ] Run `$B --watch-windows 120`. While it runs, do each of these and watch for a line printed within about 1 s:
     - [ ] open a new window (`+` line);
     - [ ] close a window (`−` line);
     - [ ] switch tabs in a browser (`~ … title` line);
     - [ ] minimize a window with ⌘ M (`~ … on screen → minimized`);
     - [ ] move a window to another Space (Mission Control, drag it to another desktop). This one may only show once you switch Spaces.
   - [ ] At the end it prints `reading the list … on the main thread: … ms` (target under 1 ms) and the CPU share (target about 0%). Record both: ________
3. **A frozen app doesn't slow Segue down.** Segue waits at most 0.25 s for any one app.
   - [ ] Open TextEdit with a document, then freeze it for 30 seconds. The `kill -CONT` runs by itself at the end:

     ```sh
     open -a TextEdit; sleep 2; kill -STOP $(pgrep -x TextEdit); sleep 30; kill -CONT $(pgrep -x TextEdit)
     ```

   - [ ] During the 30 seconds, press ⌥ Space and esc five times. The switcher appears without a noticeable delay each time.
   - [ ] Menu › Debug › Timing summary: the max for ⌥ Space is under about 250 ms. Record it: ________
4. **Idle CPU.**
   - [ ] Open Activity Monitor › CPU and find Segue. Leave the Mac idle (no switching) for 10 minutes. Segue's % CPU stays at 0.0 and its CPU Time barely moves. Record the CPU Time before and after: ________

## 5. Focus

**Why:** switching has to work for all four kinds of window: on screen, on another Space, in a hidden app, and minimized. The targets are 100 ms from the request to the window having focus, or 400 ms for a minimized window, because of the animation.

1. **Prepare one window of each kind.** For example, with TextEdit, Notes and Safari:
   - **on screen:** any window on this Space, behind the terminal;
   - **other Space:** a window on another desktop;
   - **app hidden:** click an app and press ⌘ H;
   - **minimized:** a window minimized with ⌘ M.
2. **Find their ids.** Run `$B --dump-windows`. The `kind` column shows `on screen`, `other Space`, `app hidden` or `minimized`; note one `id` for each.
3. **Focus each one.** Run `$B --focus <id>` for each id, switching back to the terminal between runs. Each should print `[ok] … focus confirmed N ms after the request`. Record each time:
   - [ ] on screen: ____ ms
   - [ ] other Space: the Space switches. ____ ms
   - [ ] app hidden: the app un-hides. ____ ms
   - [ ] minimized: the window un-minimizes. ____ ms
4. **No hang while focusing a minimized window.** This one is optional.
   - [ ] Open Instruments (Xcode › Open Developer Tool › Instruments) and choose **Time Profiler**. In the target menu at the top left, pick the running Segue, then press Record.
   - [ ] Minimize a window, then switch to it with ⌥ Tab. Stop recording.
   - [ ] In the track for Segue's main thread, there's no solid block of activity longer than about 16 ms around the switch. Record the longest: ________

## 6. Panel and keys

**Why:** this is the heart of M1. The switcher has to appear within one display frame of the key press (16 ms), never steal keys you didn't mean for it, and handle your kanata setup.

**Hold mode (⌥ Tab).**

- [ ] Hold ⌥, tap Tab quickly, and release ⌥ immediately (under about 100 ms). You switch to the window you used before, and nothing appears on screen. Do it twice: you go back and forth between two windows.
- [ ] Hold ⌥ and press Tab, then keep holding ⌥. After about 100 ms, the grid of windows appears under the notch.
  - [ ] Tab moves the selection forward and ⇧ Tab moves it back.
  - [ ] ◀ ▶ ▲ ▼ move the selection too.
  - [ ] Releasing ⌥ switches to the selected window.
  - [ ] Pressing esc closes the grid. Releasing ⌥ afterwards does nothing.

**Tap mode (⌥ Space).**

- [ ] Press ⌥ Space and release it. The grid appears and stays open.
  - [ ] ◀ ▶ move the selection, and return switches.
  - [ ] esc closes it.
  - [ ] Pressing ⌥ Space again also closes it.
- [ ] During a hold (⌥ held, grid showing), press Space. The grid stays open after you release ⌥ (tap mode).

**Special places.**

- [ ] Make an app full screen (green button). Both ⌥ Tab (held) and ⌥ Space show the grid over it.
- [ ] Connect the Dell. Click a window on the Dell, then show the grid. It appears at the top of the Dell, under a drawn "virtual notch".

**Speed.** The timing summary records every show since launch. The first show after launch and the first after connecting a display are listed separately, because they used to be slow (44–66 ms in M0).

1. - [ ] Quit and reopen Segue, so the summary starts empty: `pkill -x Segue; open /Applications/Segue.app`.
2. - [ ] Press ⌥ Space then esc, 20 times, at a normal pace.
3. - [ ] Hold ⌥ Tab until the grid shows, then press esc and release, 20 times.
4. - [ ] Connect the Dell, wait 2 seconds, click a window on it, and press ⌥ Space once.
5. - [ ] Menu › Debug › **Timing summary**. Record the two lines (`⌥ Space: …` and `hold: …`) and the `first shows` lists: ________
   - Pass: each median is at most 16 ms (`PASS`), and each first show is also within 16 ms.
   - [ ] If a first show is over 16 ms, try the always-on panel and measure again:

     ```sh
     defaults write $ID KeepPanelOnScreen -bool true
     pkill -x Segue; open /Applications/Segue.app
     ```

     Repeat steps 2–5, and also record Segue's idle CPU and Energy Impact (Activity Monitor › Energy, 10 idle minutes) with the setting on and with it off.

**Edge cases.**

- [ ] Start a download in Safari, or anything else that opens a window in the background. Then do a quick ⌥ Tab. You land on the window you used before the current one, not on the new window.
- [ ] Click the desktop, so no window has focus, then do a quick ⌥ Tab. You land on your most recently used window.
- [ ] Menu › **Pause Segue**. The icon changes to a pause symbol. ⌥ Tab and ⌥ Space now reach other apps as if Segue weren't running. Unpause.
- [ ] **A frozen Segue doesn't freeze your keyboard.** Click into a TextEdit document, then run this in a terminal. It resumes Segue by itself after 15 s:

  ```sh
  kill -STOP $(pgrep -x Segue); sleep 15; kill -CONT $(pgrep -x Segue)
  ```

  Switch to TextEdit straight away and type. Typing may stall for a moment, then works normally within a few seconds. Record how long it stalled: ________

**kanata and stray Shift.** In M0, ⌥ Tab was sometimes counted as ⇧ Tab, probably because kanata added Shift. This check captures what kanata actually sends. The log records only modifier keys and navigation keys, never letters you type.

1. - [ ] Menu › Debug › **Log raw key events** (a check mark appears).
2. - [ ] In a terminal, save the key log to a file:

   ```sh
   /usr/bin/log stream --info --predicate 'subsystem == "io.github.kkoichi276052.segue" AND category == "keys"' | tee ~/segue-keys.log
   ```

3. - [ ] Do about 20 ⌥ Tab holds, typing normally in between (including spaces). Whenever the selection moves **backwards** when you pressed plain Tab, note the time.
4. - [ ] Stop the log with ⌃ C and turn **Log raw key events** off again.
5. - [ ] Look in `~/segue-keys.log` near the times you noted. Record what you find: ________
   - `raw flagsChanged key 56` (left Shift) or `key 60` (right Shift) means a Shift press or release reached macOS.
   - `flags 0x…` shows which modifiers were down. 0x20000 is Shift and 0x80000 is ⌥.
   - `kbType`, `sourceState` and `sourcePID` show where the event came from. kanata's virtual keyboard should look different from the built-in one.
   - If you can't make it happen in 20 holds, record that.

**Daily typing.**

- [ ] Over a normal day with Segue running, note any key that went missing, doubled, or came out wrong in other apps: ________

## 7. Switcher view

**Why:** the cards have to stay readable with many windows open, and moving through them has to feel instant.

- [ ] With many windows open (30 or more if you can), show the grid. The titles are readable. If the windows don't all fit, the grid shows a page and says "N of M shown". Moving the selection past the edge brings the selected card into view.
- [ ] Holding Tab to move through many cards feels instant. Optional: Instruments › **Animation Hitches** shows no hitches while doing this.
- [ ] Windows with Japanese titles show their titles correctly.
- [ ] The flash: in M0, releasing ⌥ at about 106–155 ms showed the grid and hid it again almost at once. Try releasing just after the grid would appear. Does the brief flash bother you? If it does, try a longer delay and relaunch, then record the value you like: ________

  ```sh
  defaults write $ID ShowDelayMs -int 130
  ```

- [ ] Clicking a card switches to that window. Clicking outside the grid closes it.
- [ ] Turn on VoiceOver (⌘ F5), show the grid and move the selection. VoiceOver reads each window's title as the selection moves. Turn VoiceOver off with ⌘ F5.

## 8. Previews

**Why:** window images come from a cache that's refreshed in the background, because each capture takes about 34 ms. Needs Screen Recording (step 2).

- [ ] **Memory before previews.** Just after launch, before showing the grid, open Menu › Debug › Timing summary and record the `memory (physical footprint)` line: ____ MB
- [ ] Show the grid with ⌥ Space. Images fill in after it appears, the selected card first. With about 20 windows, all images are in within about 1 s.
- [ ] Show it 10 more times, switching windows in between. Then open Timing summary and record:
  - [ ] the `⌥ Space` and `hold` lines: medians about the same as in step 6: ________
  - [ ] the `captures:` line (median about 34 ms) and the blank count: ________
  - [ ] the `cache:` line (60 MB or less): ________
  - [ ] the physical footprint again. It should be no more than 60 MB above the first number, and 100 MB or less in total: ____ MB
- [ ] **Nothing is captured while the grid is hidden**, except one capture right after each switch.
  1. Open Timing summary and note `n=` on the `captures:` line.
  2. Don't use Segue for 2 minutes, then open Timing summary again. `n` is unchanged.
  3. Do one quick ⌥ Tab, wait a second and check again. `n` went up by exactly 1.
- [ ] While images are being captured, does macOS 27 show a screen-recording indicator in the menu bar (a purple or orange icon, or "Segue is recording your screen")? Does it stay after the grid closes? Record: ________
- [ ] **Without Screen Recording.** Turn Segue off in the Screen Recording pane and relaunch. Cards show app icons and titles instead of images, and switching still works. Timing summary says "Screen Recording is off". Turn it back on and relaunch.

## 9. Search

**Why:** search has to work through a real text field, so the Japanese input method works, and it must never leave keyboard focus in the wrong place.

- [ ] ⌥ Space, then type part of a window title. A search bar appears under the notch and the cards narrow down as you type. ◀ ▶ choose, and return switches.
- [ ] Hold ⌥ and press Tab, then type a letter while still holding ⌥. Then release ⌥. The switcher stays open, and further typing goes into the search bar.
  - Known limitation: letters typed while ⌥ is still held come through Segue's event tap, so they skip the input method. After ⌥ is released, typing goes through the input method normally.
  - [ ] While ⌥ is still held, ◀ ▶ and return work on the results.
- **Japanese input.**
  - [ ] ⌥ Space, switch to Japanese input (right ⌥), type a word that's in a Japanese window title, and convert it.
  - [ ] While the word is still being converted, the arrows and return work inside the conversion and don't move the selection.
  - [ ] After you confirm the word, the matching window is selected, and return switches to it.
- [ ] Type full-width letters (for example ＳＡＦ with Japanese input in full-width mode). They find the half-width title ("Safari").
- [ ] With some search text typed, press esc. The search clears. Press esc again and the switcher closes. The app that was in front before is still in front, and typing goes into it straight away.
- [ ] While the search bar has the keyboard, the menu bar still shows the menus of the app that was in front, not Segue's. Segue never becomes the active app.

## 10. Daily use

**Why:** the situations that only come up in real use.

- [ ] **Launch at login.** Menu › **Launch at Login** (a check mark appears). If the menu shows a warning about approval, approve Segue in System Settings › General › Login Items. Log out and back in: Segue's icon is in the menu bar.
- [ ] **Displays.** Open the grid with ⌥ Space, then unplug the Dell. The grid closes. Show it again: it's on the MacBook screen. Plug the Dell back in, click a window there and show it: it's on the Dell.
- [ ] **Apps coming and going.** During a hold, quit an app with the mouse (Dock › Quit), or have an app launch. Nothing crashes, the cards update, and the selection stays on a sensible card.
- [ ] **Spaces.** Open the grid with ⌥ Space, then swipe to another Space with three fingers. The grid closes.
- [ ] **Sleep.** Close the lid for a minute (or Apple menu › Sleep), wake the Mac, and use ⌥ Tab. It works.
- [ ] **Changing the hotkey.**

  ```sh
  defaults write $ID TapHotkey "ctrl+option+space"
  pkill -x Segue; open /Applications/Segue.app
  ```

  ⌃ ⌥ Space now opens the switcher, plain ⌥ Space doesn't, and the menu names the new key. Undo it with `defaults delete $ID TapHotkey` and relaunch.
- [ ] **A week of daily use.** Use Segue instead of ⌘ Tab for a week. Keep a short log of crashes, lost or wrong keys, and switches that went to the wrong window, with the date and what you were doing. If Segue crashes, the report is in Console › Crash Reports (look for Segue).

## Results

Fill this in as you go. It maps onto the M1 targets in [§10 of the spec](../docs/SPEC.md#m1-findings).

| Target | Your result |
|---|---|
| Hotkey to first frame: median within 16 ms (step 6) | ⌥ Space: · hold: |
| First show after launch and after connecting the Dell, within 16 ms (step 6) | |
| About 0% CPU while hidden, 10 idle minutes (step 4) | |
| 100 MB or less with 20+ previews; within 60 MB of the baseline (step 8) | |
| Focus for all four kinds of window, with times (step 5) | |
| Panes that list Segue; tap without relaunch? (step 2) | |
| Recording indicator during captures (step 8) | |
| What kanata sends for a stray Shift (step 6) | |
| Preferred show delay (step 7) | |
| Missing real windows or extra helper windows (step 4) | |
| Week of daily use: crashes, lost keys, wrong switches (step 10) | |
