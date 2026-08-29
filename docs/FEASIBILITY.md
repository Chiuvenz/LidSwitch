# Feasibility result

Tested on 2026-08-29 with:

- MacBook Air `Mac17,3`, Apple M5
- macOS 26.5.2 (25F84)
- Redmi 27 NU connected through USB-C DisplayPort

The throwaway read-only prototype answered the feasibility question:

- `AppleClamshellState` reported the closed lid correctly.
- `SLSGetDisplayList` and `SLSConfigureDisplayEnabled` both resolved from
  SkyLight on this macOS build.
- SkyLight exposed the active external display (`id=2`), inactive built-in
  display (`id=1`), and an unidentified placeholder (`id=3`).
- Hardware identity can therefore be used to avoid toggling placeholders;
  fixed display IDs are not required.

The prototype was absorbed into `CLidSwitch` and removed. The production
bridge adds a last-active-display guard, filters redundant operations, prefers
an app-lifetime CoreGraphics configuration, and falls back to a session
configuration when required. Normal app termination also restores the layout.

The SkyLight technique was independently checked against the MIT-licensed
[Clamless](https://github.com/TCXM/clamless) implementation. LidSwitch retains
its own smaller state machine because its desired direction is the reverse:
lid open means built-in only; lid closed means external only.
