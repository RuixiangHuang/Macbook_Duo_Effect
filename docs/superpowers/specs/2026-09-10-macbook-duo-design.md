# MacBook Duo — approved design

Native macOS menu bar utility for the built-in MacBook display. Closed lid is 0°. The user sets threshold x (default 90°). At angle >= x, remove all visual effects immediately. Below x, project a virtual image plane anchored at x onto the moving lid, fixed at the bottom hinge, and progressively increase darkness and Gaussian blur with a smooth curve. User clarified and approved the projection behavior during implementation. The virtual viewer is 2.5 screen-heights away, centered on the reference plane; cap pose difference at 75 degrees to avoid singular projection. Maximum dimming is 65%. Maximum blur and enabled state are adjustable and persisted. Opening reverses the effect. Normal system sleep remains intact.

Use IOKit HID feature reports to read the hinge sensor. Invalid or unavailable readings must clear the display. Use ScreenCaptureKit excluding this application's windows, Core Image Gaussian blur, and a non-interactive overlay on the internal display. Capture is local and memory-only. Screen Recording permission is requested through a visible user action. No external dependencies, no private window-server APIs. Deployment floor: macOS 14, Apple Silicon.

Provide a menu bar status, Chinese settings window, permission state, threshold and blur sliders, short self-expiring preview, pause and quit. Stop capture when clear, paused, sleeping or unavailable. Capture failures clear the overlay. A generation token rejects obsolete frames and capture-start completions.

Capture at Retina backing resolution, scaling blur radius by backing scale. Keep system sleep, display sleep and session inactivity as separate suspension reasons.

Validation: threshold and invalid-input tests; HID report decoding tests; compile and bundle verification; real hardware sensor probe; launch/UI inspection. Physical lid movement and system screen-recording approval may require the user.
