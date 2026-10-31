# Segue — Specification

> **Segue is the final product name**, chosen for the idea of moving smoothly between working contexts. Earlier drafts used "Noren" as a working name and "Axle" for the ring-based design concept.
> Status: **Draft 0.1** · Last updated: 2026-10-22 · Current prototype: [`prototypes/03-axle-workspaces.html`](../prototypes/03-axle-workspaces.html)
>
> Sections are marked where they record a decision the owner made (**Decided**) versus a direction proposed during prototyping that still needs confirmation (**Proposed**). See the [decision log](#15-decision-log).

## 1. Summary

Segue is **a better Cmd-Tab and window manager for macOS**, driven from the keyboard. One view shows your **workspaces** (saved window layouts) and the **windows** inside them, and gets you to any of them in a few keystrokes. From the same view you can arrange windows: snap one to half the screen, send it to another workspace, or close it.

It replaces Cmd-Tab for switching windows and Mission Control for seeing where things are.

The interface lives at the MacBook notch, with a virtual notch on other displays. That gives it a recognizable look, but the notch is where the app appears, not what the app is. Switching and window management come first. When the two conflict, usability wins over the notch design.

## 2. Problem

- **Cmd-Tab switches apps, not windows.** Two editor windows or three browser windows look identical.
- **Seeing what's elsewhere is slow.** To check another desktop today you open Mission Control, move the pointer to the top edge so the desktop strip expands, find a tiny thumbnail and click it. It's mostly mouse work with small previews.
- **Setups don't come back.** Getting a project's windows back into place (editor on the left, browser on the right, terminal below) is manual every time.
- **Arranging needs another tool.** Moving a window to another desktop, or snapping it to half the screen, needs the mouse or a separate utility.

## 3. Users

Primary users are keyboard-heavy Mac users (developers, designers, writers) who:

- juggle several projects a day on a MacBook with a notch, often with an external display;
- already use tools like Raycast, AltTab or Rectangle;
- switch windows dozens to hundreds of times a day.

## 4. Goals and non-goals

### Goals for v1

| ID | Goal |
|---|---|
| G1 | See where everything is at a glance: every workspace's layout, full size, without hovering. |
| G2 | Reach any window or workspace in 3 keystrokes or fewer after the hotkey (target). |
| G3 | Save a window layout as a workspace and bring it back with one key, including opening apps that aren't running. |
| G4 | Arrange and move windows from the same view: halves, full screen, centered, send to another workspace, close. |
| G5 | A distinctive, hardware-native look: the interface grows out of the notch and returns into it. This supports G1–G4 and never takes priority over them. |
| G6 | Lightweight: no visible lag, near-zero CPU when idle, modest memory. |

### Not in v1

- An extension or plugin platform.
- A general app launcher (Raycast replacement). Search covers windows and workspaces only ([Q7](#14-open-questions)).
- Automatic tiling. The "hide everything else" window-manager mode comes later ([§6.6](#66-bringing-a-workspace-back)).
- Managing macOS Spaces (desktops). Workspaces are the app's own concept.
- Mac App Store distribution ([§9](#9-architecture-proposed)).
- Syncing workspaces across Macs.

## 5. Concepts

| Term | Meaning |
|---|---|
| **Workspace** | A saved window layout: which app windows, and where on screen. Numbered 1–9 in a fixed order. |
| **Slot** | One window position inside a workspace: the app, an optional document, folder or URL, and a frame stored as fractions of the screen. |
| **Loose windows** | Open windows that belong to no workspace. They have their own island at the end of the ring. |
| **Active workspace** | The workspace most recently brought back. |
| **Ring** | The row of islands around the notch. |
| **Island** | A black circle on the ring that stands for one workspace and shows a small map of its layout. |
| **Track** | The path islands move along. The default follows the notch's outline. |
| **Preview** | The large miniature of the selected workspace below the ring. |
| **Side glance** | A dimmed, blurred sliver of the previous or next workspace's preview at the screen edge. |
| **Peek island** | An island at either end of the ring, half hidden behind the top edge and blurred. |
| **Tap mode** | Opened with ⌥ Space; stays open until you switch or press esc. |
| **Hold mode** | Opened by holding ⌥ and pressing Tab; switches when you let go of ⌥. |

## 6. Experience

### 6.1 Opening it

| Input | Behavior | Status |
|---|---|---|
| ⌥ Space | Tap mode: open the ring at the active workspace. | Decided |
| Hold ⌥, press Tab | Hold mode: cycle recently used windows across all workspaces. Letting go of ⌥ switches. ⇧ Tab goes back. | Decided |
| While holding ⌥ | Arrow keys move the selection. esc cancels without switching. Typing a letter keeps the interface open and starts a search ([§6.5](#65-search-proposed)). | Decided |
| Hold ⌥, press ` | Cycle only the current app's windows. | Proposed; not in M1 |
| Direct hotkeys | For example ⌃⌥1–9 brings back workspace N without opening the interface. Optional per-app hotkeys replace "pinning". | Decided (pins replaced by hotkeys); key choice proposed |

- All hotkeys are configurable. ⌥ Space is already used by some apps, so onboarding must detect and explain conflicts ([Q6](#14-open-questions)).
  - Registering a hotkey (Carbon `RegisterEventHotKey`) only fails when another app registered the same keys the same way. Apps that catch keys with event taps can't be detected.
  - In M1, a hotkey that fails to register shows in the menu bar item, and keys are changed with `defaults write`. Explaining conflicts in onboarding comes in M4.
- **Key remappers.** Tools like kanata and Karabiner can change what arrives. With a tap-hold key, for example Space as Shift when held, the tap reaches macOS only on release, and holding it past its timeout adds Shift to other keys. Arrows give hold mode a way to move back that doesn't depend on Shift.
- Hold mode has a show delay (0–250 ms). A quick ⌥ Tab tap switches to the previous window without flashing the interface. The default is to be tuned; the prototype suggests about 100 ms. When the interface does show, it fades in over about 100 ms and hides at once, so a release just after the delay doesn't read as a flash.

### 6.2 The ring

- **Track (Decided: follow the notch).** Islands sit on a track that follows the notch's outline:
  - the selected island directly under the notch;
  - its neighbors along the notch's bottom edge;
  - the next ones beside its corners;
  - the rest slide behind the top edge.
- **Order.** Islands keep a fixed order by workspace number, for spatial memory, with the loose-windows island last. The ring wraps around.
- **Peek islands (Decided).** The two islands at the ends peek out half hidden and blurred, to hint that more exist.
- **Island content:**
  - a small white map of the workspace's layout;
  - dashed blocks for slots whose apps aren't open;
  - a number badge (1–9);
  - a dot on the active workspace.
- **Opening.** Islands emerge from the notch and slide along the track to their places, staggered from the center outward.
- **Kept in settings during testing.** Track shape (follow the notch, ellipse, circle) and distance from the notch. Prototype default: follow the notch, 44 pt.

### 6.3 The preview

- **What it shows.** Below the selected island, joined to it by a short black "neck", a miniature of the workspace shows every window at its saved position, with a current image of its content.
- **Size (Decided: as large as possible).** It runs to the bottom of the screen: 1056 × 660 pt on a 1280 × 800 reference screen.
- **Side glances (Proposed: thin).** The previous and next workspaces peek in at the screen edges.
  - Because the preview keeps the screen's 16:10 shape, its height limits it before its width does. That leaves about 110 pt of unused space on each side.
  - Thin glances (about 84 pt) use that space at no cost to the preview.
  - Wide glances (170 pt) shrink the preview by about a sixth.
  - Clicking a glance turns the ring.
- **Turning the ring** slides the previews in the same direction as the islands.
- **Labels.** The workspace name, window count and key hints sit inside the bottom edge of the preview.
- **Apps that aren't open** appear as dashed placeholders with the app icon and "Opens when you switch".
- **Loose windows** show as a grid instead of a layout.

### 6.4 Picking and acting on a window

- **Picking.** ▼ picks a window (the most recent one in the workspace). ◀ ▶ move between windows. ▲ or esc goes back to the ring.
- **Focusing.** return focuses the picked window and brings its workspace back.
- **Actions on the picked window:**

| Keys | Action |
|---|---|
| ⇧ ◀ / ⇧ ▶ | Snap to the left / right half |
| ⇧ ▲ | Full screen (fills the visible area; not macOS full-screen mode) |
| ⇧ ▼ | Centered |
| ⇧ 1–9 | Send to workspace N. The window flies into that island, which pulses. |
| ⇧ delete | Close the window |

- **Saving.** Actions update the workspace immediately ([Q3](#14-open-questions)).

### 6.5 Search (Proposed)

- **Starting.** Typing any letter while the ring is open starts a search. There's no permanent search field; the key hints say "type to search". Typing a letter during a hold also starts a search, and the interface stays open after ⌥ is released (Decided).
- **Input (Decided).** Search uses a real text field, not keys read through the event tap, so input methods work, for example Japanese.
- **Where it appears.** The ring tucks back into the notch, and the selected island stretches into a search bar directly under the notch. The bar is joined to the notch above and to the results below. The notch itself can't show anything because it's the camera cutout with no pixels, so the space right below it is the closest place that can.
- **What it searches.** Window titles, app names and workspace names. The top 6 results show as a grid in the preview, and workspace results show their layout map.
- **Keys.** ◀ ▶ choose a result, return goes there, esc clears the search and brings the ring back, and a second esc closes.
- **Not in v1:** apps that aren't open ([Q7](#14-open-questions)).

### 6.6 Bringing a workspace back

Pressing return on a workspace, or on a window inside it:

1. Launches the apps for slots that have no matching window, reopening their document, folder or URL where one was saved.
2. Moves and resizes the matched windows to their saved frames.
3. Raises them in order of recent use and focuses the most recent one, or the picked window.

Two modes:

- **Bring to front (v1, Decided).** Other windows stay where they are, behind.
- **Hide everything else (later, Decided as the long-term direction).** Windows outside the workspace are hidden, so switching feels like changing desktops. The candidate technique is moving windows just off-screen, which is AeroSpace's approach. Performance and memory must stay within [§8](#8-non-functional-requirements).

**Switch animation (Proposed).** Windows fly from their position in the preview to their real position while the interface retracts into the notch. macOS doesn't let one app animate another app's real windows, so the app animates captured images in its own overlay and reveals the real windows at the end. An "Instant" option skips it.

### 6.7 Motion principles

- **Animation never blocks input.** Keys pressed during an entrance apply immediately.
- **Interruptible springs.** Everything moves on springs that keep their speed when retargeted. Prototype defaults: stiffness about 420, bounce about 16%.
- **The notch is origin and destination.** Things come out of it and go back into it.
- **Liquid black shapes.** Black shapes merge with the notch and with each other like liquid (a "metaball" effect).
- **Reduce Motion.** Fades only, with no movement and no fly-in animation.

### 6.8 Keyboard reference

| Context | Key | Action |
|---|---|---|
| Anywhere | ⌥ Space | Open the ring (tap mode) |
| Anywhere | Hold ⌥ + Tab / ⇧ Tab | Recent windows across workspaces; let go to switch |
| Hold | ◀ ▶ ▲ ▼ | Move the selection |
| Hold | esc | Cancel without switching |
| Hold | Any letter | Search; stays open after ⌥ is released |
| Anywhere | Hold ⌥ + ` | Current app's windows |
| Ring | ◀ ▶ | Turn the ring |
| Ring | 1–9 | Jump to workspace N |
| Ring | return | Bring the workspace back |
| Ring | ▼ | Pick a window in the preview |
| Window | ◀ ▶ | Next / previous window |
| Window | ▲ or esc | Back to the ring |
| Window | return | Focus the window |
| Window | ⇧ + arrows | Snap: left, right, full, centered |
| Window | ⇧ 1–9 | Send to workspace N |
| Window | ⇧ delete | Close the window |
| Ring or window | Any letter | Search |
| Search | ◀ ▶ / return / esc | Choose / go there / clear |
| Any | esc | Back one step, then close |

### 6.9 Mouse and trackpad

- Hovering selects only when the pointer actually moves, so content gliding under a still pointer never steals the selection.
- Clicking an island brings that workspace back. Clicking a window focuses it. Clicking a side glance turns the ring. Clicking outside closes.

### 6.10 Displays

- **Notch detection.** Use `NSScreen.safeAreaInsets` together with `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (macOS 12 and later).
- **Which display.** Show on the display with the focused window. On a display without a notch, draw a virtual notch (a black tab at the top center) for the interface to grow out of.
- **Everywhere.** Appear over full-screen apps and on every macOS Space.
- **Frames.** Store workspace frames as fractions of a display's visible area. Workspaces that span several displays are an open question ([Q4](#14-open-questions)).

### 6.11 Visual language

- **Look.** Pure black and matte, with no glass. It should read as the hardware itself extending, and stand apart from macOS's Liquid Glass look.
- **Type.** The system font. White text on black, and dark pills behind labels that sit over window content.
- **Accessibility.** VoiceOver announces the selected workspace or window. Respect Reduce Motion and Increase Contrast. Every action is reachable from the keyboard.

### 6.12 Managing workspaces (Proposed)

- **Create.** "Save current screen as workspace" from the ring (key to be decided, for example ⌘ S). It records the visible windows, their apps and frames, and, where available, their document, folder or URL.
- **Edit.** Rename, reorder (which changes the numbers) and delete, both in the ring and in Settings.
- **Saving.** Changes made with the window actions in [§6.4](#64-picking-and-acting-on-a-window) save automatically.

### 6.13 Onboarding and permissions

| Permission | Needed for | Required? |
|---|---|---|
| Device Control and Data Access (macOS 27); Accessibility (macOS 26) | Listing, focusing, moving and resizing windows, and the hold-mode event tap. On macOS 27, granting this one pane was enough for both the Accessibility and the Input Monitoring checks in S6. That was observed with Terminal as the host and is re-checked for the app in M1. | Required |
| Input Monitoring (macOS 26) | Possibly needed separately for the event tap on macOS 26. Checked in a macOS 26 VM before the beta. | To be confirmed on 26 |
| Screen Recording | Window images for previews and the fly-in animation. Also the titles of windows on other Spaces: those come from the Window Server list, which hides titles without this permission. Without it the app shows icon-and-title cards. | Optional, recommended (Decided) |

- Explain each permission before macOS asks for it.
- Recover gracefully when a permission is revoked.
- Permissions are tied to the app's code signature, so even development builds need a stable signing identity. Ad-hoc-signed builds lose their permissions on every rebuild.

## 7. Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | Global hotkeys: ⌥ Space (tap mode), ⌥ Tab hold with switch-on-release | P0 |
| FR-02 | Inventory of every window across apps, including minimized windows and windows on other macOS Spaces | P0 |
| FR-03 | Focus a specific window | P0 |
| FR-04 | Workspaces: create from the current screen, rename, reorder, delete; saved to disk | P0 |
| FR-05 | Ring with fixed order and wrap-around, on a track that follows the notch | P0 |
| FR-06 | Preview showing windows at their saved positions with images, or icon-and-title cards without Screen Recording | P0 |
| FR-07 | Bring a workspace back: launch missing apps, apply frames, raise and focus | P0 |
| FR-08 | Window actions: halves, full, centered, send to workspace, close | P0 |
| FR-09 | Search windows and workspaces | P0 |
| FR-10 | Hold mode across all workspaces' windows; same-app variant | P0 |
| FR-11 | Permissions onboarding and the no-Screen-Recording fallback | P0 |
| FR-12 | Notch detection; virtual notch on other displays; show on the active display | P0 |
| FR-13 | Accessibility: Reduce Motion, VoiceOver labels, full keyboard access | P0 |
| FR-14 | Side glances and peek islands | P1 |
| FR-15 | Fly-into-place switch animation | P1 |
| FR-16 | Direct hotkeys per workspace and per app | P1 |
| FR-17 | Settings: hotkeys, track shape and distance, preview option, show delay, launch at login | P1 |
| FR-18 | "Hide everything else" mode | P2 |
| FR-19 | Thirds, quarters and custom snap layouts | P2 |
| FR-20 | Search apps that aren't open (launcher behavior) | P2 |
| FR-21 | Workspaces that span several displays | P2 |

## 8. Non-functional requirements

### Performance targets (to be confirmed by the spikes in §10)

- **Speed to first frame.** From hotkey to first frame in 1–2 display frames (about 8–16 ms at 120 Hz). The panel is created ahead of time, and the window inventory is kept current through system notifications, never built when the hotkey is pressed.
- **Idle cost.** About 0% CPU when hidden, with no polling.
- **Memory.** About 100 MB or less, including the window-image cache (low-resolution images, least recently used dropped first, with a configurable cap).
- **Bringing back.** Arranging a 3–6 window workspace takes under 300 ms, not counting app launch time.

### Reliability

- Accessibility calls run off the main thread with a messaging timeout (`AXUIElementSetMessagingTimeout`), so one frozen app never freezes the interface.
- Apps quitting or launching mid-interaction never break the view.

### Privacy and security

- No network access in v1 apart from update checks.
- Window images stay in memory. They are never written to disk or sent anywhere.
- No analytics by default.
- Signed and built with the hardened runtime. Development builds use a free Apple Development certificate (Decided). Whether releases use a paid Developer ID with notarization is open ([Q11](#14-open-questions)).

### Compatibility

- Primary target: Apple silicon MacBooks with a notch. Any Mac works with the virtual notch.
- **Minimum macOS 26 (Decided).** Development and M1 testing are on macOS 27. macOS 26 is checked in a VM before the beta (M5).

## 9. Architecture (proposed)

- **Stack.** Swift with AppKit: a non-activating `NSPanel` above the menu bar, drawn with Core Animation. The liquid metaball effect comes from a Metal shader or a SwiftUI layer effect, to be compared in a spike. No Electron or web views.
- **Distribution.** Outside the Mac App Store, because controlling other apps' windows through Accessibility requires running outside the App Sandbox. Updates via Sparkle.

### Components

| Component | Responsibility | Module |
|---|---|---|
| `HotkeyService` | Register global hotkeys (Carbon `RegisterEventHotKey`) | SegueSystem |
| `HoldMonitor` | Detect ⌥ held and released for hold mode (event tap); optional raw key-event log | SegueSystem |
| `SwitcherState` | The hold, tap and search state machine: show delay, quick switch, selection, release, cancel | SegueCore |
| `WindowInventory` | Keep the list of windows current: `NSWorkspace` notifications, `AXObserver`, `CGWindowListCopyWindowInfo`; recently-used order | SegueSystem, with merging and order in SegueCore |
| `PrivateAPI` | SkyLight focus and `_AXUIElementGetWindow`, resolved at run time, with a launch self-check and fallbacks | SegueSystem |
| `WindowController` | Focus, raise, move, resize, close and hide windows through Accessibility, off the main thread. M1 has only the focus part (`WindowFocuser`). | SegueSystem |
| `SnapshotService` | Capture window images with ScreenCaptureKit; small least-recently-used cache | SegueSystem, with the cache policy in SegueCore |
| `SearchRanker` | Match and rank windows (and later workspaces) for a query | SegueCore |
| `WorkspaceStore` | Load and save workspaces (JSON in `~/Library/Application Support/<App>/`) | SegueSystem (M2) |
| `Restorer` | Bring a workspace back: match windows to slots, launch missing apps, apply frames | SegueSystem (M2) |
| `OverlayPanel` | The notch panel and its views: ring, preview, search | SegueUI |
| `SpringAnimator` | Interruptible spring motion shared by all views | SegueUI (M4) |
| `PermissionsCoordinator` | Onboarding, permission status, fallbacks | SegueSystem, with its window in SegueUI |
| `Settings` | User defaults and the settings window. M1 has only the defaults. | App target |

### Private APIs (Decided)

The product uses two private calls that S1 relies on, as AltTab does:

- **`_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`** (SkyLight) focus a window on another Space.
- **`_AXUIElementGetWindow`** maps an Accessibility window to its window ID.
- **`SLSCopySpacesForWindows` and `SLSCopyManagedDisplaySpaces`** (SkyLight, read only) tell which Space a window is on and each display's Spaces in order. Added in M1: on macOS 27 the focus call above brings the window's app forward but doesn't switch Space, so Segue presses the "Move left/right a space" shortcut first ([M1 findings](#m1-findings)).

Notarization doesn't check for private APIs; App Store review does, and the App Store is already ruled out. The risk is a macOS update breaking them, so:

- Both live in one small `PrivateAPI` module. SkyLight is loaded with `dlopen`, and its symbols are resolved at run time.
- A self-check at launch logs which calls work. The menu bar item shows when the app is running on fallbacks.
- Without SkyLight, windows on other Spaces are still listed, and choosing one activates its app.
- Without `_AXUIElementGetWindow`, windows are matched by process, title and frame.
- The remote-token lookup (`_AXUIElementCreateWithRemoteToken`) is not used: S1 found it slow and it missed some apps' windows.

### Project structure (Decided)

```
app/
  project.yml              XcodeGen spec; the generated Segue.xcodeproj is ignored by git
  Segue/                   App target: entry point and wiring, Info.plist (menu bar only), entitlements, assets
  SegueKit/                Local Swift package
    Sources/SegueCore/     Pure logic, no AppKit
    Sources/SegueSystem/   macOS integration
    Sources/SegueUI/       Panel and views
    Tests/SegueCoreTests/
spikes/                    The M0 record: frozen, not a dependency of the app
```

- **SegueCore** holds the logic that can be tested without macOS services: merging the window lists, recently-used order, `SwitcherState`, `SearchRanker` and the cache policy. `swift test` runs its tests headless in seconds.
- **SegueSystem** holds everything that talks to macOS: Accessibility, `CGWindowList`, `PrivateAPI`, ScreenCaptureKit, the event tap, hotkeys and permissions.
- **SegueUI** holds the panel, the switcher view and the permissions window. The app target wires the three together.
- XcodeGen keeps the project definition as a reviewable text file. Run `xcodegen generate` after pulling.

**From the spikes.** Code is copied and adapted, never linked, so changes to the app can't alter the M0 measurements.

| From | To | Notes |
|---|---|---|
| `SpikeKit/Windows.swift`: `_AXUIElementGetWindow`, `cgWindows()`, the `AX` helpers, the messaging timeout | `PrivateAPI`, `WindowInventory` | The `AX` setters and `visibleFrameInAXCoordinates` wait for M3 |
| `SpikeKit/Focus.swift`: the SkyLight front-process call and the make-key event records | `PrivateAPI`, `WindowFocuser` | `OffSpace.element` (remote tokens) is dropped |
| `SpikeKit/Permissions.swift` | `PermissionsCoordinator` | |
| `SpikeKit/Measure.swift`: `measure`, `Stats`, `residentMemory` | SegueCore, for the debug timing summary | |
| `s1-windows`: the focus routine | `WindowFocuser` | |
| `s6-panel`: panel level and collection behavior, `notchRect`, the Carbon hotkey, the event tap and its re-enable, the hold logic | `OverlayPanel`, `HotkeyService`, `HoldMonitor`, `SwitcherState` | The hold logic is rewritten as a testable state machine |
| `s4-capture`: the capture setup, the blank-image check, the size filter | `SnapshotService` | |

These stay in the spikes: `Report`, `Arguments`, `columns`, and `s2-arrange`'s frame setting, which comes back in M3.

### Data model (sketch)

```swift
struct Workspace: Codable {
    var id: UUID
    var name: String
    var order: Int            // 1–9 on the ring
    var slots: [Slot]
}

struct Slot: Codable {
    var id: UUID
    var bundleID: String      // e.g. "com.apple.Safari"
    var titleHint: String?    // helps match an existing window
    var documentURL: URL?     // document, folder or web URL to reopen
    var frame: CGRect         // fractions (0–1) of the display's visible area
    var displayHint: String?  // which display, if more than one
}

struct WindowRef {            // runtime only, never saved
    var windowID: CGWindowID
    var pid: pid_t
    var element: AXUIElement
    var title: String
    var frame: CGRect
    var isMinimized: Bool
    var workspaceID: UUID?
}
```

**Matching windows to slots.** Match by app, then by how closely the title matches, then by the last known window ID. Ties go to the most recently used window.

## 10. Technical risks and spikes

Facts that shape the risks:

- Apple has no public API for macOS Spaces. Tools that work with Spaces (AltTab, yabai) rely on private APIs, which can break with macOS updates. Workspaces avoid most of this by not depending on Spaces.
- Moving a window to another macOS Space has no supported method. yabai needs System Integrity Protection partly disabled for it.

| Spike | Question | Pass when |
|---|---|---|
| S1 Window list | List every window, including minimized ones and those on other Spaces. Match Accessibility windows to window IDs. Focus any specific window. | 50 windows listed in under 50 ms when warm; any window focuses reliably, including on other Spaces |
| S2 Arranging | Set frames through Accessibility for Safari, Chrome, VS Code (Electron), Xcode, Terminal and Finder | 3–6 windows arranged in under 300 ms, 95% or more succeed, no visible bounce |
| S3 Hiding | Compare moving windows off-screen, minimizing and hiding the app (for the later mode) | One option is fast and flicker-free, with acceptable side effects on the Dock, Cmd-Tab and Stage Manager |
| S4 Window images | Cost of single-frame ScreenCaptureKit captures; memory for about 20 cached images; whether hidden, off-screen or other-Space windows can be captured | 15 ms or less per capture at preview size; cache at 60 MB or less |
| S5 Restoring | Launch apps with documents, folders or URLs; match windows to slots | Correct match for 90% or more of a test set |
| S6 Panel and keys | Non-activating panel over the menu bar and full-screen apps; detect ⌥ held and released; which permission it needs | First frame within 16 ms of the hotkey; works over full-screen apps |

### M0 spike plan (Proposed)

The spikes run on a MacBook with a notch. They call macOS-only APIs (Accessibility, `CGWindowList`, ScreenCaptureKit, `NSPanel`, event taps), so they can't be built or measured on another OS, and the notch and permission prompts only exist on the target hardware.

One Swift package under `spikes/`, with one executable per spike. Each prints its measurements and a pass or fail against the targets above.

| Spike | Executable | What it does |
|---|---|---|
| S1 | `s1-windows` | Lists windows with `CGWindowListCopyWindowInfo` and Accessibility, matches them by window ID, times the warm listing, and focuses a chosen window, including on another Space |
| S2 | `s2-arrange` | Applies frames to 3–6 windows across Safari, Chrome, VS Code, Xcode, Terminal and Finder; reports time per window, success rate and whether each window ends where it was set |
| S4 | `s4-capture` | Times single-frame `SCScreenshotManager` captures at preview size, measures memory for about 20 cached images, and tries minimized, hidden and other-Space windows |
| S5 | `s5-restore` | Saves the current Space's standard windows as slots (app, title, AXDocument, frame), then launches missing apps (with local documents), matches windows to slots by document, exact title, title words or as the app's remaining window, and sets the saved frames |
| S6 | `s6-panel` | Shows a non-activating panel over the menu bar and full-screen apps, times hotkey to first frame, detects ⌥ held and released with an event tap, and records which permission macOS asks for |

Assumptions to confirm:

- macOS 14 is the minimum for the spikes, because `SCScreenshotManager` needs it. The product's minimum is macOS 26 (decided 2026-10-22).
- S1 may use the private `_AXUIElementGetWindow` call to match Accessibility windows to window IDs, as AltTab does. Whether the product needs it is part of what S1 finds out.

**Build status and results (2026-10-22).** The four executables are in [`spikes/`](../spikes/) and build with Xcode 27.1 (Swift 6.4) on macOS 27.0.1 (26A434), MacBook Pro Mac14,9. Built-in display: notch 185 × 32 pt, 120 Hz. Run from T3 Code with Accessibility, Screen Recording and Input Monitoring granted. The S1, S2 and S4 runs had up to 89 windows across several Spaces, minimized windows and a hidden app. S6 was run by hand.

| Spike | Result | Notes |
|---|---|---|
| S1 | Pass | **Listing:** with 89 app windows (several Spaces, 6 minimized, one app hidden), the warm full listing (Window Server + Accessibility) took a median of 29.5 ms (p95 37.1 ms), or 16.6 ms projected for 50. With 20 windows it was 7–10 ms. Cold: 281–466 ms. Accessibility only returns the current Space's windows, so windows elsewhere have no AX element. **Focus:** windows on the current Space go through Accessibility, windows elsewhere through the private SkyLight calls AltTab uses (`_SLPSSetFrontProcessWithOptions` plus a make-key event record). Each case passed, measured as focus confirmed after the request: current Space 25–36 ms; other Space 24–32 ms (Zed, Ghostty, Finder, T3 Code), with the Space switching; a hidden app's window 34 ms; minimized windows 42–91 ms, but the unminimize call itself blocks for 260–284 ms because of the animation. Looking up the AX element by remote token isn't needed for focus. It found Finder's and T3 Code's within 43 IDs but not Zed's or Ghostty's within 2,000, and the search made the request take 59–204 ms, so the product should call SkyLight directly. `--focus-all` not run, to avoid cycling through every Space. |
| S2 | Pass (8 apps) | Safari, Chrome, T3 Code (Electron, in place of VS Code, which isn't installed), Terminal and Finder, in a 3 × 2 grid, 5 rounds: median 28.6–42.0 ms for 5 windows, p95 119–206 ms (always the first round). 25/25 placed. No bounce detected in the 300 ms after setting; nobody watched the screen. Only 5 of the 25 landed within 2 pt, because the 504 × 475 pt cells are smaller than most apps allow: Safari's minimum width is 574, Finder's 525, T3 Code's minimum is 840 × 620, and Terminal sizes in character cells (503 × 469). Position was exact every time. The spike now counts "as close as the app allows" (origin exact; size at the app's minimum or within 20 pt below) as a success and reports exact landings alongside it. Layouts will need to know each app's minimum size, because a clamped window overlaps its neighbour. **Xcode** (second run, with Safari, T3 Code and Finder in a 2 × 2 grid): 20/20 placed, 15 within 2 pt (all 5 others were T3 Code at its minimum size), median 38.3 ms for 4 windows, no bounce. VS Code isn't needed: it stood for Electron apps, and T3 Code is Electron. **Zed** (its own GPU toolkit) and **Zen** (Firefox-based), third run with T3 Code in a 2 × 2 grid: 15/15 placed, median 29.6 ms for 3 windows, no bounce. Zed landed within 2 pt every time; Zen stopped at its minimum height of 495 pt. |
| S4 | Fail on time; memory passes; decided: cache and refresh | **Time:** warm single-frame `SCScreenshotManager` capture: median 34–36 ms at 0.7× (7–20 windows), 35.5 ms at 0.2× and 33.7 ms at 1.4×. Cost doesn't depend on image size, so it's per-call overhead and smaller images won't meet the 15 ms target. **Alternatives, measured:** requesting all windows at once took 156 ms for 7 and 407 ms for 20 (about 20 ms per window), so the system mostly serializes them. One `SCStream` per window delivered its first frame 81 ms (median) after starting, then about 29 complete frames a second at a 30 fps cap even for untouched windows, and delivered no frames at all for a hidden app's windows. **States:** single captures got content from on-screen (8/8), minimized (4/4), hidden-app (4/4) and other-Space windows (3/4 in the first run; the blank one was a 350 × 350 T3 Code utility window). In the 20-window run, 4 blank "off screen" captures were Chrome helper windows about 100 pt tall, not user windows; the spike's size filter should exclude them. **Memory:** 19.8 MB for 20 images at 0.7× (smaller windows) and 42.9 MB projected from larger ones, both under 60 MB; 187 MB projected at 1.4×. The spike first crashed in `CGS_REQUIRE_INIT` and now calls `NSApplication.shared` before capturing. See the decision log for the cache-and-refresh decision. |
| S5 | Pass for placing windows; content is the app's job (owner, 2026-10-29) | Two rounds on the owner's apps, 2026-10-29. **Placing:** every matched window went back to its saved frame (2/2, then 6/6), including a minimized one, which was unminimized. **Distinct apps** (T3 Code, Muse, YouTube Music, even with an empty title) matched correctly every time. **Relaunch:** Zen, quit with ⌘Q, came back with 3 windows after 9.9 s but showed a new tab and its release notes, not the saved pages, so the strict "same window" score was 50%. The owner accepts this: Segue launches the app and places its windows, and what they show is the app's session restore. **Closed windows of a running app:** reopening works for local documents (Ghostty reopened in its folder); a browser window can't come back, because Zen doesn't expose its page. **Edge cases, not handled for now (owner):** remote projects (Zed's AXDocument was a path on the SSH host), SSH sessions in a terminal, and windows on other Spaces, which Accessibility can't see or move. Matching took 112 ms for 6 slots. |
| S6 | Pass, except the first show | Runs by hand from the T3 Code terminal and from Terminal.app. **Timing:** warm ⌥ Space reached the screen 12.3–19.8 ms after the key event. The handler ran within 0.3 ms and the panel was committed within 4.3 ms, so most of the time is waiting for a display frame. Warm ⌥ Tab holds, timed from the end of the show delay: 11.7–18.2 ms. The first show of each run took 44–58 ms, so the product should prepare the panel ahead of time. **Full screen:** shown and visible over full-screen Terminal, for both ⌥ Space and a hold. **Hold and release:** release was detected every time. Releases at 76–83 ms switched without showing the panel. Releases at 106–155 ms showed it and hid it again almost at once, a possible flash to look at in the product. **Permissions:** macOS 27 has no Accessibility pane in Privacy & Security; "Device Control and Data Access" takes its place. With nothing granted, ⌥ Space still works (it needs no permission), but the active event tap can't be created. macOS asked once, for Device Control and Data Access. After it was granted, Terminal was listed only there, not under Input Monitoring, yet the spike reported Accessibility and Input Monitoring as granted and created the active tap. Screen Recording still reported missing for Terminal, though that pane's description mentions recording the screen. The listen-only tap without permissions wasn't tried. **External display:** on a DELL S2725QC (2560 × 1440, no notch), the spike detected no notch and drew a virtual one. The panel showed there and was visible. ⌥ Space: 66.5 ms the first time, then 10.5 and 13.4 ms. Hold mode wasn't tried on it. **Counting:** ⌥ Tab presses were sometimes counted as Shift-Tab ("#-4", "#0"), but counted forward in another run. The likely cause is kanata, which turns Space into Shift when held. Key remappers like it are a real-world case: they can add Shift, and tap-hold keys reach the app late, which these timings don't include because they start at the event macOS receives. |

Before starting on the Mac: install Xcode (or Command Line Tools with Swift 6), note the macOS version and MacBook model, and grant Accessibility and Screen Recording to the terminal the spikes run from when macOS asks. The spikes move, focus and capture real windows. They write nothing to disk and use no network.

### M1 findings

**Status (2026-10-29): M1 closed, with known issues.** The app is built ([`app/`](../app/)), 73 unit tests pass, and the owner checked it hands-on on macOS 27.0.1. The owner chose to close M1 and start M2, and to handle the known issues when they get in the way, rather than finish every check first.

| Target | Result | Status |
|---|---|---|
| Hotkey to first frame within 16 ms median | ⌥ Space median 54.6 ms, hold median 29.2 ms, first show 69.2 ms. Segue's own work is 3–10 ms; 24–50 ms pass between handing the panel to macOS and the first display-link callback. Each show logs its steps (`show steps` in the `ui` log) for when it matters. | Known issue; the owner doesn't notice lag |
| About 0% CPU while hidden | 0.0% idle with input off; 0.095% while tracking focus changes | Met; 10-minute check with input on not run |
| 100 MB or less with previews | 27 MB physical footprint with 12 previews | Met |
| Focus works for all four kinds of window | Current Space, other Space (after the Space move below), click and keyboard all work | Met; hidden app and minimized not checked separately |
| Window list | 7.8–16.6 ms warm; reading it on the main thread 0.0001 ms | Met |
| Search keystroke within 16 ms for 100 windows | median 0.1 ms, max 0.7 ms offscreen | Met |
| Hands-on | Hold, quick switch, cancel, ⇧ Tab and arrows; ⌥ Space; search in English, Japanese and full width; esc; full-screen apps; the external display's virtual notch; clicking cards and outside; Pause; previews (22.6 ms per capture, none blank); many windows shrink the cards | Met |

**Not tested, by choice:** freezing apps (`kill -STOP`), the kanata key log, VoiceOver, running without Screen Recording, launch at login, sleep, and paging (reached only beyond about 45–50 windows).

Notes:

- **Helper windows.** Off-screen windows under 100 pt, or with an empty title, are dropped. On the owner's desktop this removed 7 of the 22 windows S1 listed. All 7 looked like helper windows; the owner hasn't confirmed this yet.
- **SkyLight for every focus.** Segue focuses through SkyLight on the current Space too, not only on other Spaces as step 5 planned, because macOS can refuse to activate a background app otherwise. This is the order AltTab uses. Without SkyLight, it falls back to Accessibility, as S1 did.
- **Typing during a hold.** Letters typed while ⌥ is still held come through the event tap and skip the input method. Once ⌥ is released, typing goes into the search field and input methods work.
- **Signing.** Ad-hoc builds lose their permissions on every rebuild, so permission checks need a build signed with the owner's Apple Development certificate (`app/Local.xcconfig`).
- **Command-line checks.** An option the binary doesn't know now prints an error and exits. Before this change, a stale build given a new check option started the full app from the terminal for about 10 minutes, which registers the hotkey and can install the event tap.
- **Other Spaces on macOS 27.** SkyLight brings the window's app forward but doesn't switch Space. Segue now presses "Move left/right a space" first and waits for it (about 1 s of macOS animation), which needs those shortcuts on. See the [decision log](#15-decision-log).
- **Cards on click.** Clicking a card didn't switch until the card view accepted the first click (`acceptsFirstMouse`).
- **Permissions on macOS 27.** Segue is listed under Device Control and Data Access and under Screen & System Audio Recording, not under Input Monitoring, and the event tap works.

## 11. Milestones

| Milestone | Scope |
|---|---|
| M0 | Spikes S1, S2, S4, S6 (S3 and S5 can follow). Done 2026-10-22; results in [§10](#m0-spike-plan-proposed). S5 done 2026-10-29. |
| M1 | Window switcher: hold mode across all windows, search, previews, no workspaces yet. The owner uses it daily. See the [M1 plan](#m1-plan-decided). Built 2026-10-23, closed 2026-10-29 with known issues ([findings](#m1-findings)). |
| M2 | Workspaces: ring, preview, save and bring back, launch missing apps |
| M3 | Window actions: snap, send, close; loose windows |
| M4 | Polish: motion, side glances, peek islands, virtual notch, settings, onboarding |
| M5 | Private beta with keyboard-launcher users and a one-week usage study |
| Later | "Hide everything else" mode; search for apps that aren't open; workspaces across displays |

### M1 plan (Decided)

**Goal.** A window switcher the owner uses every day instead of Cmd-Tab: hold mode across all windows, search and previews. No workspaces yet.

**Starting point from M0.**

- Listing windows, focusing every kind of window, the panel over full-screen apps, detecting ⌥ held and released, and capturing window images all work on the target Mac.
- **The window list must be a cache.** The full listing takes 29.5 ms for 89 windows, too slow to build when the hotkey is pressed. It's built at launch and kept current by notifications.
- **Previews come from a cache too.** A capture costs about 34 ms whatever its size, so images are refreshed in the background.
- **The first show needs pre-warming.** It took 44–66 ms against a 16 ms target.
- **Other Spaces are a special case.** Windows there have no Accessibility element. Focusing them needs SkyLight, and their titles come from the Window Server list, which needs Screen Recording.

**Scope.**

| Area | In M1 |
|---|---|
| Hold mode | ⌥ Tab and ⌥ ⇧ Tab across all windows in recently-used order, including minimized, hidden-app and other-Space windows. Arrows move the selection while ⌥ is held. Releasing switches; esc cancels. A release before the show delay (100 ms, adjustable) switches to the previous window without showing anything. |
| Tap mode | ⌥ Space opens the same switcher and keeps it open. There's no ring until M2. return focuses; esc clears the search, then closes. |
| Search | Typing in tap mode, or typing a letter during a hold, filters by window title and app name. It uses a real text field, so input methods work. |
| View (Proposed) | A grid of window cards hanging from the notch, or from a virtual notch on other displays, on the display with the focused window. Each card shows an image, the app icon and the title. All windows show at once when they fit. The grid fades in over about 100 ms and hides at once. Clicking a card focuses it; clicking outside closes. |
| Previews | Cached images show at once and are refreshed in the background, selected card first. Cards show the app icon and title while there's no image, or without Screen Recording. Images stay in memory only, in a least-recently-used cache capped at 60 MB. |
| Permissions | A small first-launch window asks for Device Control and Data Access (Accessibility on macOS 26), then optionally Screen Recording. Missing or revoked permissions show in the menu bar item. |
| App shell | Menu bar item only, with no Dock icon: status, Pause, a Debug menu and Quit. Launch at login. Hotkeys and the show delay are changed with `defaults write`. |
| Diagnostics | Debug menu: dump windows, private-API self-check, raw key-event log, timing summary (hotkey to first frame). Logs go to `os.Logger`; timings use signposts. |

**Not in M1.**

- Workspaces, the ring and islands, and bringing workspaces back (M2).
- Window actions: snap, send and close (M3).
- The same-app ⌥ ` variant and direct hotkeys.
- A settings window or hotkey recorder.
- From M4: polished onboarding, conflict explanations, spring motion, the metaball effect, side glances, peek islands and the fly-in animation.
- Sparkle updates, Developer ID and notarization.
- Testing on macOS 26. The deployment target is 26, but M1 is tested on 27 only.
- Spikes S3 and S5.

**How steps are checked.**

- The SegueCore logic has unit tests that run with `swift test`: list merging, recently-used order, `SwitcherState`, `SearchRanker` and the cache policy.
- Anything that touches macOS is checked on the MacBook through the Debug menu and signpost timings, against a checklist in the step's pull request. There are no UI tests.
- Each step is one pull request. It builds, passes its tests and leaves the app runnable.

**Build order.**

| Step | What | Checked by |
|---|---|---|
| 1 Skeleton | `app/project.yml`; the `SegueKit` package with its three modules; a menu-bar-only app; free Apple Development signing; `.gitignore` for the generated project. The bundle identifier is chosen here, once, because permissions are tied to it. | `xcodegen generate` and `xcodebuild` build cleanly; `swift test` passes; no Dock icon. A permission granted before a rebuild is still granted after it. |
| 2 Permissions | `PermissionsCoordinator` and the first-launch window. Permission status is checked once a second, but only while that window is open. | After `tccutil reset All <bundle id>`, Segue goes from first launch to fully granted without a terminal. Record which System Settings panes list Segue on macOS 27, and whether the event tap works without a relaunch. A revoked permission shows in the menu bar at the next show. |
| 3 Private APIs | `PrivateAPI`: SkyLight focus and `_AXUIElementGetWindow`, resolved at run time, with the launch self-check and fallbacks. | The self-check reports both calls available on 27.0.1. A debug default that pretends each is missing exercises its fallback. |
| 4 Inventory and recency | `WindowInventory`, off the main thread with a 0.25 s messaging timeout, kept current by `NSWorkspace` notifications and one `AXObserver` per app. Recently-used order comes from focus changes, starting from the Window Server's front-to-back order. Helper windows are filtered out. | Unit tests for merging, filtering and order. The dump matches `s1-windows`'s user windows on the same desktop. Opening, closing, renaming, minimizing and moving a window to another Space show up within 1 s. Reading the list on the main thread takes under 1 ms. A stopped app (`kill -STOP`) delays nothing by more than 0.25 s. CPU stays at 0.0% over 10 idle minutes. |
| 5 Focus | `WindowFocuser`: Accessibility on the current Space, SkyLight elsewhere, unminimizing off the main thread. | Debug focus for each S1 case: current Space, other Space, hidden app and minimized. Focus is confirmed within 100 ms, or 400 ms for minimized windows. No main-thread hang over 16 ms. |
| 6 Panel and keys | The pre-warmed `OverlayPanel` at the notch or a virtual notch; the Carbon ⌥ Space hotkey; the event tap for hold mode, which swallows keys only during a hold or while the switcher is open; `SwitcherState`; Pause in the menu. The content is a plain list of titles. | Unit tests for the state machine: show delay, quick switch, ⇧ Tab, arrows, esc, release, and a letter starting a search. A timing summary over 20 ⌥ Space presses and 20 holds, including the first after launch and the first after connecting the external display: the median and the first show are within 16 ms. If not, try the always-on transparent panel and record its idle cost. A quick ⌥ Tab never shows a frame. The switcher works over a full-screen app. With Segue stopped (`kill -STOP`), typing in other apps recovers within a few seconds. The raw key log shows what kanata sends when a stray Shift appears; the finding goes in [§10](#m0-spike-plan-proposed). **Daily use starts here.** |
| 7 Switcher view | The card grid with icon-and-title cards, selection, fade-in, click to focus, and VoiceOver announcing the selection. | 89 windows stay readable. Moving the selection keeps every frame within 16 ms. Japanese titles render. A release at 106–155 ms no longer reads as a flash (the owner's call). |
| 8 Previews | `SnapshotService` and its cache. It refreshes on show, selected card first, one capture at a time, and captures the window you just left after a switch. | Show timings are unchanged from step 7. 20 cards refresh within about 1 s. With 20 or more images, resident memory stays within 60 MB of the step-7 baseline. Nothing is captured while the switcher is hidden, except after a switch, and idle CPU stays about 0%. With Screen Recording off, cards still work. Record whether macOS 27 shows a recording indicator. |
| 9 Search | The text field in tap mode, and a letter during a hold switching to search. `SearchRanker` ignores case and full-width versus half-width forms, and ranks word-prefix matches first, then substring, then scattered-letter matches, with ties going to the most recently used. Titles of windows on other Spaces come from the Window Server list, or else from the last title seen through Accessibility. | Ranking unit tests, including Japanese and full-width text. Typing Japanese through the input method finds a Japanese-titled window. Each keystroke updates the results within 16 ms for 100 windows. esc leaves the previously active app in front, unchanged. |
| 10 Daily-use hardening | Launch at login (`SMAppService`); connecting and disconnecting displays; apps launching or quitting during a hold; Space switches; sleep and wake; keys changed with `defaults`. | A checklist covering each of these passes on the MacBook, followed by a week of daily use with issues logged. |

**Done when.**

- The owner switches with Segue instead of Cmd-Tab for a week, with no crash and no lost keyboard input.
- On the MacBook, every target is met:
  - hotkey to first frame within 16 ms median, including the first show (or a recorded exception);
  - about 0% CPU while hidden;
  - 100 MB resident or less with previews;
  - focus works for all four kinds of window.
- Findings are recorded in [§10](#m0-spike-plan-proposed) and decisions in [§15](#15-decision-log).

## 12. Success measures

- **Setup:** share of new users who grant permissions and create a workspace in their first session.
- **Habit:** by day 7 of the beta, the share of window switches made with the app instead of Cmd-Tab, and invocations per day.
- **Speed:** median keys and milliseconds from hotkey to switch. The prototype already logs both.
- **Quality:** 99.5% or more crash-free sessions; success rate for bringing workspaces back.

## 13. Similar products

Based on product pages and general knowledge as of October 2026. Verify before using externally.

| Product | What it does | How this app differs |
|---|---|---|
| Cmd-Tab, Mission Control (built in) | App switching; overview of windows and Spaces | Window-level, keyboard-first, full-size previews |
| AltTab | Window switcher with thumbnails | Adds workspaces, window actions and the notch interface |
| Raycast | Launcher with window-management commands | A visual overview of workspaces and windows |
| Rectangle / Rectangle Pro, Moom | Snapping and saved layouts | Switching and overview in the same view |
| AeroSpace, yabai, Amethyst | Tiling window managers | Visual and keyboard-driven, no config files; yabai needs System Integrity Protection changes for some features |
| Stage Manager (built in) | Groups of windows in a side strip | Keyboard-first, full-size previews |
| Workspaces (Apptorium) | Opens sets of apps, files and URLs | Switching and arranging, not just opening |
| NotchNook, Boring Notch, Alcove, ProNotch, Notchy, Notchwell, Vibe Island | Launchers, media controls, shelves and agent status at the notch | Window and workspace navigation |

## 14. Open questions

| ID | Question |
|---|---|
| Q3 | When you move a window yourself, outside the app, should its workspace update automatically, or only when you save? |
| Q4 | Workspaces across several displays: one layout per display, or one workspace spanning displays? |
| Q5 | Does a newly opened window join the active workspace automatically? |
| Q6 | What are the default direct hotkeys (⌃⌥1–9 is proposed), and how does onboarding explain hotkey conflicts (M4)? The hold and tap keys and M1's conflict handling are decided ([§15](#15-decision-log)). |
| Q7 | Should search also find apps that aren't open (launcher behavior)? |
| Q8 | In "hide everything else" mode, how does it coexist with macOS Spaces and full-screen apps? |
| Q9 | What is the business model and price? |
| Q10 | Final default for the preview: biggest, thin glances (current proposal) or wide glances? |
| Q11 | How are releases signed: a paid Developer ID with notarization (about US$99 a year; no Gatekeeper warning), or an unnotarized build signed with a stable self-made certificate (free, but users must choose "Open Anyway" in System Settings on first launch)? Ad-hoc signing is ruled out, because users would have to grant permissions again after every update. Decide before M5. |

## 15. Decision log

| Date | Decision | Status |
|---|---|---|
| 2026-10-05 | Support both hold mode (⌥ Tab, switch on release) and tap mode (⌥ Space, stays open) | Decided |
| 2026-10-05 | Islands show pinned and running apps | Superseded the same day |
| 2026-10-05 | Pins are replaced by per-app hotkeys; search is a key advantage; when few windows are open, show them all at once | Decided |
| 2026-10-05 | Accept the Screen Recording permission for window images, with an icon-and-title fallback | Decided |
| 2026-10-11 | Axle chosen over the Columns and Loupe concepts; closer to the notch, bigger windows | Decided |
| 2026-10-11 | The core job is navigation across workspaces, windows and apps; a workspace is a saved window layout, not a macOS Space | Decided |
| 2026-10-11 | Scope: navigator plus light window actions now; full window manager ("hide everything else") eventually, watching performance and memory | Decided |
| 2026-10-11 | Workspaces are the top level of the view | Decided |
| 2026-10-12 | The ring follows the notch's outline instead of a circle | Decided |
| 2026-10-12 | Peek islands at the ends of the ring; preview runs to the bottom of the screen | Decided |
| 2026-10-12 | Thin side glances by default | Proposed |
| 2026-10-12 | Next build step: technical spikes in Swift | Decided; scheduled for a later session |
| 2026-10-13 | Search bar under the notch, stretched out of the selected island; no permanent search field | Proposed |
| 2026-10-13 | The product is a better Cmd-Tab and window manager; the notch is where it appears, not its identity. Naming no longer needs to reference the notch or the ring. | Decided |
| 2026-10-13 | Name shortlist: Fusuma and Noren | Superseded by final name decision on 2026-10-20 |
| 2026-10-13 | Noren becomes the working name (repository: `noren`); final name still open | Superseded by final name decision on 2026-10-20 |
| 2026-10-20 | Segue chosen as the final product name: moving smoothly between working contexts. Naming question Q2 resolved. | Decided |
| 2026-10-21 | Technical spikes are built and measured on a MacBook with a notch, not on the Linux machine; plan recorded in [§10](#m0-spike-plan-proposed) | Decided |
| 2026-10-22 | Window previews show the last cached image immediately and refresh it in the background, because a single ScreenCaptureKit capture takes about 34 ms whatever its size ([S4](#m0-spike-plan-proposed)) | Decided |
| 2026-10-22 | Minimum macOS 26. Built and tested on 27; 26 checked in a VM before M5. Q1 resolved. | Decided |
| 2026-10-22 | Hold mode: ⌥ Tab forward, ⌥ ⇧ Tab back, arrows move while ⌥ is held, esc cancels. M1 logs raw key events to diagnose remappers: kanata adds Shift when Space is held for 150 ms or more. | Decided |
| 2026-10-22 | Search in M1: ⌥ Space opens the switcher and keeps it open; typing a letter during a hold also starts a search. Search uses a real text field so input methods work. | Decided |
| 2026-10-22 | Hotkey conflicts in M1: a failed registration shows in the menu bar, and keys are changed with `defaults write`; no settings window until M4. The same-app ⌥ ` variant waits until after M1. Q6 narrowed to direct hotkeys and onboarding. | Decided |
| 2026-10-22 | Private APIs accepted: SkyLight focus and `_AXUIElementGetWindow`, isolated in one module, resolved at run time, with a launch self-check and public fallbacks. The remote-token lookup is dropped. See [§9](#private-apis-decided). | Decided |
| 2026-10-22 | Slow first show: pre-warm the panel at launch and on display changes. If the first show still misses 16 ms, keep the panel on screen but transparent, and measure the idle cost. The panel fades in over about 100 ms and hides at once; the show delay is adjustable. | Decided |
| 2026-10-22 | Permissions in M1: a small first-launch window asks for Device Control and Data Access, then optionally Screen Recording, with no relaunch unless macOS requires one. Revoked permissions show in the menu bar. Polished onboarding stays in M4. | Decided |
| 2026-10-22 | Project structure: an XcodeGen `project.yml`, plus a local `SegueKit` package with SegueCore, SegueSystem and SegueUI. Spike code is copied, not linked; `spikes/` stays as the M0 record. See [§9](#project-structure-decided). | Decided |
| 2026-10-22 | Development builds are signed with a free Apple ID "Apple Development" certificate. Whether to pay for the Developer Program is deferred to before M5 ([Q11](#14-open-questions)). | Decided |
| 2026-10-22 | M1 plan recorded in [§11](#m1-plan-decided): scope, non-goals, ten build steps and how each is checked | Decided |
| 2026-10-22 | M1 view: a grid of window cards under the notch, with all windows at once when they fit | Proposed |
| 2026-10-23 | Focus goes through SkyLight on every Space, not only other Spaces, with Accessibility as the fallback ([M1 findings](#m1-findings)) | Proposed |
| 2026-10-23 | Helper windows are filtered out: off-screen windows under 100 pt or with an empty title | Proposed |
| 2026-10-23 | Accept for M1 that letters typed while ⌥ is still held skip the input method | Proposed |
| 2026-10-29 | Choosing a window on another macOS Space moves there with the "Move left/right a space" shortcut, then focuses it. The macOS slide (about 1 s) is accepted for M1; instant switching is a later, standalone experiment. It needs those shortcuts on in Keyboard Shortcuts › Mission Control. | Decided |
| 2026-10-29 | Bringing a workspace back means launching its apps and placing their windows. What the windows show (a browser's pages, a terminal's session) is left to each app's own restore. Remote projects, SSH sessions and windows on other Spaces are edge cases, not handled for now. | Decided |
| 2026-10-29 | Workspaces are usually 2–3 windows, sometimes 4 (owner). Layouts and tests are sized for that. | Decided |

## 16. Prototypes

All three are single HTML files that run in a browser. They simulate the apps, windows and window images.

| File | What it explores |
|---|---|
| [`01-notch-islands.html`](../prototypes/01-notch-islands.html) | v0.1 motion study: app icons as black islands budding from the notch; pins on the left, recent apps on the right; hold and tap modes; search inside the islands |
| [`02-notch-concepts.html`](../prototypes/02-notch-concepts.html) | v0.2: three concepts compared (Columns, Axle, Loupe); spring motion; genie-style switch; show every window when few are open |
| [`03-axle-workspaces.html`](../prototypes/03-axle-workspaces.html) | v0.3, current: workspace ring following the notch; full-height preview with side glances; peek islands; window actions; search under the notch; "bring to front" vs "hide everything else" |
