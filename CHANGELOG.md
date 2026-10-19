# Changelog

## 0.1.1 — 2026-10-19

- Ignore stale offline display IDs when a real external display is already active.
- Restore only the external display IDs observed before LidSwitch disabled them.
- Debounce display reconfiguration notifications and retry transient CoreGraphics contention.
- Include display serial numbers in diagnostic output.

## 0.1.0 — 2026-08-29

- Initial open-source release.
- Automatically switch between built-in-only and external-only layouts based on lid state.
- Add last-display safety guard, manual recovery, login launch, diagnostics, and five state-machine tests.
- Add the first LidSwitch app icon.
