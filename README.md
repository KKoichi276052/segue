# Segue

A better Cmd-Tab and window manager for macOS, driven from the keyboard. One view shows your workspaces (saved window layouts) and the windows inside them. You can get to any of them in a few keystrokes, and snap, send or close windows from the same view. The interface appears at the MacBook notch.

**Status:** specification, browser prototypes and M0 spike code and results. No app code yet.

## Contents

| Path | What it is |
|---|---|
| [`docs/SPEC.md`](docs/SPEC.md) | Product and technical specification, open questions and decision log |
| [`prototypes/`](prototypes/) | Interactive HTML prototypes. Open any file in a browser, click the simulated screen, then press ⌥ Space. |
| [`spikes/`](spikes/) | M0 technical spikes in Swift: one executable per spike, each printing pass or fail against the spec's targets |

## Next step

Review the [M0 spike results](docs/SPEC.md#m0-spike-plan-proposed) in section 10 of the spec and decide what goes into M1. See [`spikes/README.md`](spikes/README.md) for how to run the spikes.
