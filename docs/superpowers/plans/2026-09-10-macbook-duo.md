# MacBook Duo Implementation Plan

**Goal:** Deliver a runnable native menu bar application implementing the approved angle-dependent blur.
**Architecture:** A pure effect model and HID report decoder feed a menu bar controller. ScreenCaptureKit supplies an application-excluding capture to Core Image and a click-through built-in-display overlay.
**Tech Stack:** Swift, AppKit, SwiftUI, IOKit, ScreenCaptureKit, Core Image.
**Spec:** docs/superpowers/specs/2026-09-10-macbook-duo-design.md

## Global Constraints
- macOS 14+, Apple Silicon; no external packages.
- At angle >= x, radius is exactly zero and the overlay is hidden.
- Closed lid is 0°; default x = 90°.
- Capture only in memory, only the internal display, exclude own application.
- On missing sensor, permission failure, sleep or pause: clear effect.

## Task 1 — Effect model and sensor
- [x] Write executable Swift assertions in Tests/main.swift for threshold, monotonic blur, invalid values, disabled state, and HID little-endian report decoding.
- [x] Run scripts/test.sh and observe missing implementation failure.
- [x] Implement Sources/EffectModel.swift and Sources/LidSensor.swift. `EffectModel.radius(angle:threshold:maximum:enabled:) -> Double`; `LidReport.angle(_:) -> Double?`.
- [x] Re-run tests and probe the real sensor using the app's --probe mode.

## Task 2 — Capture and interface
- [x] Implement Sources/BlurOverlay.swift: generation-checked stream lifecycle, app exclusion, Gaussian blur, bounded frame delivery, immediate clearing, built-in display selection.
- [x] Implement Sources/AppController.swift and Sources/main.swift: status item, settings, persisted values, bounded preview, sleep/wake and display-change recovery.
- [x] Build with scripts/build.sh, linking Apple system frameworks and signing a local .app bundle.

## Task 3 — Verification and delivery
- [x] Run tests and release build; verify Info.plist and code signature.
- [x] Run --probe and --self-check; launch application. Hardware angle 112°, internal display found.
- [ ] Complete live UI and physical-lid validation after user grants Screen Recording. Computer Use verified the new settings UI and live 102° sensor display. Actual app reports Screen Recording not authorized; enable toggle currently off. CLI preflight reported true under the invoking process context, which does not establish permission for the GUI app.
- [x] Review capture lifecycle, no-overlay-at-threshold guarantee, error paths, cleanup, and documentation.
- [x] Document installation, permission and manual lid-motion checks in README.md; deliver dist/MacBook Duo.app.

## Verification results

Model tests passed, including threshold identity, perspective bounds and darkness. Core Image synthetic render passed at 90°, 70°, 45°; inspected docs/effect-preview.png. Release build completed without warnings and code signature / Info.plist checks passed. Independent review issues (Retina resolution and separate sleep/session flags) fixed.
