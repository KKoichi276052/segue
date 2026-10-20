# Segue — Specification

> **Segue is the final product name**, chosen for the idea of moving smoothly between working contexts. Earlier drafts used "Noren" as a working name and "Axle" for the ring-based design concept.
> Status: **Draft 0.1** · Last updated: 2026-10-20 · Current prototype: [`prototypes/03-axle-workspaces.html`](../prototypes/03-axle-workspaces.html)
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
| Hold ⌥, press ` | Cycle only the current app's windows. | Proposed |
| Direct hotkeys | For example ⌃⌥1–9 brings back workspace N without opening the interface. Optional per-app hotkeys replace "pinning". | Decided (pins replaced by hotkeys); key choice proposed |

- All hotkeys are configurable. ⌥ Space is already used by some apps, so onboarding must detect and explain conflicts ([Q6](#14-open-questions)).
- Hold mode has a show delay (0–250 ms). A quick ⌥ Tab tap switches to the previous window without flashing the interface. The default is to be tuned; the prototype suggests about 100 ms.

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

- **Starting.** Typing any letter while the ring is open starts a search. There's no permanent search field; the key hints say "type to search".
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
| Accessibility | Listing, focusing, moving and resizing windows. Possibly also the system-wide keyboard listener for hold mode. | Required |
| Input Monitoring | Possibly needed for the hold-mode keyboard listener (spike S6 confirms which permission applies). | To be confirmed |
| Screen Recording | Window images for previews and the fly-in animation. Without it the app shows icon-and-title cards. | Optional, recommended (Decided) |

- Explain each permission before macOS asks for it.
- Recover gracefully when a permission is revoked.

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
- Signed with a Developer ID, notarized, and built with the hardened runtime.

### Compatibility

- Primary target: Apple silicon MacBooks with a notch. Any Mac works with the virtual notch.
- Minimum macOS version to be decided ([Q1](#14-open-questions)).

## 9. Architecture (proposed)

- **Stack.** Swift with AppKit: a non-activating `NSPanel` above the menu bar, drawn with Core Animation. The liquid metaball effect comes from a Metal shader or a SwiftUI layer effect, to be compared in a spike. No Electron or web views.
- **Distribution.** Outside the Mac App Store, because controlling other apps' windows through Accessibility requires running outside the App Sandbox. Updates via Sparkle.

### Components

| Component | Responsibility |
|---|---|
| `HotkeyService` | Register global hotkeys (Carbon `RegisterEventHotKey`) |
| `HoldMonitor` | Detect ⌥ held and released for hold mode (event tap) |
| `WindowInventory` | Keep the list of windows current: `NSWorkspace` notifications, `AXObserver`, `CGWindowListCopyWindowInfo` |
| `WindowController` | Focus, raise, move, resize, close and hide windows through Accessibility, off the main thread |
| `SnapshotService` | Capture window images with ScreenCaptureKit; small least-recently-used cache |
| `WorkspaceStore` | Load and save workspaces (JSON in `~/Library/Application Support/<App>/`) |
| `Restorer` | Bring a workspace back: match windows to slots, launch missing apps, apply frames |
| `OverlayPanel` | The notch panel and its views: ring, preview, search |
| `SpringAnimator` | Interruptible spring motion shared by all views |
| `PermissionsCoordinator` | Onboarding, permission status, fallbacks |
| `Settings` | User defaults and the settings window |

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

## 11. Milestones

| Milestone | Scope |
|---|---|
| M0 | Spikes S1, S2, S4, S6 (S3 and S5 can follow) |
| M1 | Window switcher: hold mode across all windows, search, previews, no workspaces yet. The owner uses it daily. |
| M2 | Workspaces: ring, preview, save and bring back, launch missing apps |
| M3 | Window actions: snap, send, close; loose windows |
| M4 | Polish: motion, side glances, peek islands, virtual notch, settings, onboarding |
| M5 | Private beta with keyboard-launcher users and a one-week usage study |
| Later | "Hide everything else" mode; search for apps that aren't open; workspaces across displays |

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
| Q1 | What is the minimum macOS version? |
| Q3 | When you move a window yourself, outside the app, should its workspace update automatically, or only when you save? |
| Q4 | Workspaces across several displays: one layout per display, or one workspace spanning displays? |
| Q5 | Does a newly opened window join the active workspace automatically? |
| Q6 | What are the default hotkeys, and how are conflicts handled (⌥ Space is taken by some apps)? |
| Q7 | Should search also find apps that aren't open (launcher behavior)? |
| Q8 | In "hide everything else" mode, how does it coexist with macOS Spaces and full-screen apps? |
| Q9 | What is the business model and price? |
| Q10 | Final default for the preview: biggest, thin glances (current proposal) or wide glances? |

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

## 16. Prototypes

All three are single HTML files that run in a browser. They simulate the apps, windows and window images.

| File | What it explores |
|---|---|
| [`01-notch-islands.html`](../prototypes/01-notch-islands.html) | v0.1 motion study: app icons as black islands budding from the notch; pins on the left, recent apps on the right; hold and tap modes; search inside the islands |
| [`02-notch-concepts.html`](../prototypes/02-notch-concepts.html) | v0.2: three concepts compared (Columns, Axle, Loupe); spring motion; genie-style switch; show every window when few are open |
| [`03-axle-workspaces.html`](../prototypes/03-axle-workspaces.html) | v0.3, current: workspace ring following the notch; full-height preview with side glances; peek islands; window actions; search under the notch; "bring to front" vs "hide everything else" |
