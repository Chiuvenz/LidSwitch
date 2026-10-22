# Changelog

## 0.6.1 — 2026-10-22

- Explain the app's lid-triggered screen enable/disable behavior directly in the panel.
- Replace abstract group labels with action-oriented choices: Display When Open / Display When Closed / Managed by macOS.
- Clarify each choice's opposite-lid behavior in tooltips and VoiceOver help, widening the compact picker to fit readable labels.

## 0.6.0 — 2026-10-22

- Require a recognized built-in display plus at least one additional available display before automatic switching can run.
- Pause and gray out the automatic switch when displays become unavailable, preserving user intent and group assignments for reconnection.
- Use live connection hints to count app-disabled physical displays without accepting cached offline ghosts; retain reachable app-disconnected Sidecar sessions without oscillating.
- Observe CoreGraphics display reconfiguration events without a polling timer, retaining target-first and last-screen safety checks.
- Refine device glyph sizing and move Sidecar/lock indicators inline beside device names, keeping group labels consistently centered.
- Replace hardware-derived test identifiers with synthetic fixtures and add availability/pause/reconnection regression coverage.

## 0.5.1 — 2026-10-22

- Simplify each device to a single name row; move connection details and experimental status into tooltips.
- Color device icons blue only when the actual display is active, otherwise gray, independently of group assignment.
- Identify Sidecar devices with a small AirPlay badge and require both a connected session and an active virtual display for the blue state.
- Replace outlined tabs with subtle capsule controls, using the same layout for the locked built-in display.
- Retain keyboard and VoiceOver interaction, preserve focus across refreshes, and add appearance and activity-state regression tests.

## 0.5.0 — 2026-10-22

- Replace participation checkboxes with native Open / Closed / Unmanaged segmented controls; keep the built-in display locked to the open-lid group.
- Enable the target group's physical displays before disabling the opposite group; preserve the last usable screen if closed-group targets are missing.
- Let the experimental Sidecar iPad follow either group, retaining serialized session operations and physical-display safety checks.
- Migrate previous selections to the closed-lid group without changing their stable identities or taking over unmanaged devices.
- Preserve offline group assignments, restore only app-disabled displays on release, and add group-aware diagnostics and regression tests.

## 0.4.0 — 2026-10-22

- Add experimental support for one selected Sidecar iPad, identified by its stable device UUID instead of transient display IDs.
- Disconnect the Sidecar session after the built-in display becomes available on lid open; reconnect after a physical external display is active on lid close.
- Keep Sidecar virtual displays out of SkyLight transactions and migrate the previous iPad selection when uniquely identifiable.
- Serialize asynchronous session requests, cap retries, cancel stale delayed work, and allow bounded recovery on normal quit.
- Show iPad names and experimental session status in the panel; add read-only Sidecar diagnostics and regression tests.

## 0.3.2 — 2026-10-22

- Remove the duplicate recovery button; turning off automatic switching still restores managed displays.
- Combine Quit on the left and Launch at Login on the right into a single footer row.

## 0.3.1 — 2026-10-22

- Simplify the popover by removing the status summary, persistent help text, and manual apply action.
- Explain the recovery action in its tooltip and accessibility help.

## 0.3.0 — 2026-10-22

- Replace the target-display submenu with a native translucent popover inspired by macOS control panels.
- Keep the built-in display permanently checked and allow independent participation for multiple external displays.
- Show participation separately from the current display and connection state.
- Restore a display when it is unchecked, keeping the other participants unchanged.
- Migrate the previous single-display choice and guard against recycled display IDs and duplicate same-model selections.

## 0.2.0 — 2026-10-22

- Add a target-display submenu with live display names, connection state, and selection state.
- Default to the MacBook built-in display and leave newly connected external displays under macOS control.
- Restrict automatic lid switching to the one external display explicitly selected by the user.
- Follow a selected display when macOS assigns it a new ID, while excluding offline ghost IDs.
- Restore only displays that LidSwitch disabled itself.

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
