# Ideas

Tabled concepts for Duo Effect. Nothing here is scheduled or agreed; each note
captures the intent well enough to pick up later.

## Face-tracked frozen-screen fold (partially shipped 2026-11-09)

Track the viewer's face/eye position with the camera and render the fold from
the viewer's true perspective, so the tilted picture reads as a real plane in
space seen from exactly where they sit.

**Shipped:** one-shot, user-triggered eye calibration — the Calibrate button in
settings measures the viewer's eye pose and the fold projection uses it instead
of a nominal centered viewer. The result persists until re-calibrated. See the
eye-measurement paragraph in DEVELOPMENT.md.

**Still tabled:** continuous head tracking while the lid moves, so the fold
follows you if you shift position mid-close. The built-in camera moves with the
lid and is occluded near full close, so continuous tracking would fall back to
the last measured pose (which is what ships today).

Open questions for the continuous version:

- **Occlusion:** tracking is useless once the lid has rotated down far enough
  that the camera no longer sees the face (roughly past 45° or so); blend back
  to the last measured pose well before that.
- **Hysteresis:** continuous Vision inference on the frame queue competes with
  capture and rendering; measure the budget at 120 Hz before committing.
- **Privacy:** continuous tracking is a much bigger ask than a one-second
  calibration — it would need an explicit opt-in toggle and matching messaging
  in both languages.
