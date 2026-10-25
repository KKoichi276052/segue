# Segue

A better Cmd-Tab and window manager for macOS, driven from the keyboard. One view shows your workspaces (saved window layouts) and the windows inside them. You can get to any of them in a few keystrokes, and snap, send or close windows from the same view. The interface appears at the MacBook notch.

**Status:** specification, browser prototypes, M0 spike code and results, and the M1 window switcher in [`app/`](app/). M1 is built; the owner's hands-on checks are still open.

## Contents

| Path | What it is |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Product and technical specification, open questions and decision log |
| [`prototypes/`](prototypes/) | Interactive HTML prototypes. Open any file in a browser, click the simulated screen, then press ⌥ Space. |
| [`app/`](app/) | The Segue app (M1): an XcodeGen project and the `SegueKit` package. See [`app/README.md`](app/README.md) to build and run it. |
| [`spikes/`](spikes/) | M0 technical spikes in Swift: one executable per spike, each printing pass or fail against the spec's targets |

## Next step

Run the hands-on checks in [`app/M1-CHECKLIST.md`](app/M1-CHECKLIST.md) on the MacBook, then use Segue instead of Cmd-Tab for a week. The results so far are in the spec's [M1 findings](docs/SPEC.md#m1-findings); what's still open goes there too, with decisions in section 15.
