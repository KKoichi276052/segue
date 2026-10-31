# Segue

A better Cmd-Tab and window manager for macOS, driven from the keyboard. One view shows your workspaces (saved window layouts) and the windows inside them. You can get to any of them in a few keystrokes, and snap, send or close windows from the same view. The interface appears at the MacBook notch.

**Status:** specification, browser prototypes, M0 spike code and results, and the M1 window switcher in [`app/`](app/). M1 is closed with known issues; M2 (workspaces) is next.

## Contents

| Path | What it is |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Product and technical specification, open questions and decision log |
| [`prototypes/`](prototypes/) | Interactive HTML prototypes. Open any file in a browser, click the simulated screen, then press ⌥ Space. |
| [`app/`](app/) | The Segue app (M1): an XcodeGen project and the `SegueKit` package. See [`app/README.md`](app/README.md) to build and run it. |
| [`spikes/`](spikes/) | M0 technical spikes in Swift: one executable per spike, each printing pass or fail against the spec's targets |

## Next step

Build M2, workspaces (spec [§11](docs/SPEC.md#11-milestones)), while using the M1 switcher daily. M1's results and known issues are in the spec's [M1 findings](docs/SPEC.md#m1-findings).
