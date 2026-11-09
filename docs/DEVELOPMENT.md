# Development notes

*[中文](DEVELOPMENT.zh-CN.md)* · Back to the [README](../README.md).

## Building and checking

Requires Xcode or compatible Apple Swift tooling and an Apple Development or
Developer ID signing identity in your keychain. No third-party packages. A single
identity is picked automatically; with several, set `CODE_SIGN_IDENTITY` to the
certificate SHA-1. Quit a running copy before building.

```sh
./scripts/test.sh
./scripts/build.sh
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --probe
"dist/Duo Effect.app/Contents/MacOS/DuoEffect" --self-check
```

The build refuses ad-hoc signing on purpose: it would invalidate the stored
Screen Recording grant on every rebuild. Certificate-bound signing is what keeps
an existing privacy grant valid across rebuilds. The app is signed with a local
Apple Development certificate and is not Developer ID notarized.

Running `--self-check` directly from a terminal reports the permission state of
the terminal that launched it, which is not evidence that the GUI app is granted.
Check the permission status shown in the app window instead.

## Manual acceptance

With Screen Recording granted, check that: the image blurs progressively below
the threshold and is completely clear when reopened to it; the background keeps
updating while windows move and ordinary video plays; pause and quit restore
the original image; external displays stay untouched; and no effect lingers
after lock, sleep or wake.

## Effect model

The image is fixed in space behind the panel; the panel is the viewport you look through. The eye is a pinhole: each corner of the fixed image projects onto the panel plane where the eye→corner ray crosses it, and `CIPerspectiveTransform` maps the image onto that destination quad — the hinge keeps the bottom edge in place. Writing (x, y, z) for the eye in screen-height units and δ for the lid's rotation from vertical, the image's top edge lands at (y + u·(1 − y)) / cos δ above the hinge, where u = (z − y·tan δ) / (z + tan δ·(1 − y)) is the crossing fraction along the ray. With the eye above the screen's top edge that height exceeds 1 as soon as the lid moves, so the picture's top row is drawn above the panel and clipped away: no light ray from it can get through the tilting panel, from the first degree of the fold. The projected top edge also narrows to a width fraction u, so black appears at the sides exactly where the panel looks past the image — no mask is used, only light that could not reach the eye. The eye's lateral and vertical offsets shift and pivot the projection, so the measured seat matters. The ease lives in the rotation, not the geometry: below the threshold the δ fed to the projection is itself smoothstepped over a two-degree angular band, so every rendered frame remains an exact projection of some real lid angle while the visual response starts from rest (the band also absorbs the sensor's one-degree quantization). Dimming layers the full close progress fade with the turning panel's Lambertian brightness (cos δ), so the picture darkens faster than a pure fade as it turns away, and a crease shadow scaling with sin δ darkens a short seam above the hinge. Blur radius stays driven by the close progress through its vertical mask. The perspective slider blends between the flat screen and this projection (100% is physically correct) and is a taste control, not a calibration.

The projection knows where the hinge axis is, not just where the picture is. `LidGeometry` describes the lid in screen-height units: the active area starts above the hinge axis behind a small bottom bezel (~6.5 mm), the display surface sits in front of the axis by about half the lid thickness (~4 mm), and the camera sits in the notch cut into the active area just below the top row above the menu bar (~3 mm), recessed about 1.5 mm behind the glass. Because of that offset the picture's bottom row is no longer pinned to the panel's bottom edge: as the lid swings toward the viewer the lower part of the panel looks past the picture, leaving a black strip that widens with the fold. The same offset converts the calibrated eye pose, which is measured relative to the display, into the hinge frame the projection uses. The defaults are derived from Apple's published specs — the 16-inch active area is 3456×2234 at 254 ppi (223.4 mm tall) in a 16.8 mm body, the 14-inch 3024×1964 (196.4 mm) in 15.5 mm — and live as constants in `LidGeometry`, converted with the panel's measured active height so 14- and 16-inch lids both get the right screen-height units. Settings show the detected machine (`hw.model`, e.g. “MacBook Pro 14-inch, 2024”) as the preset source; an **Advanced override** section holds the switch and four millimetre fields (hinge drop, standoff, camera inset, camera recess) for a lid measured by hand, plus a reset back to the preset. The eye pose is expressed against the vertical screen plane (90° open); the projection rotates it into the frozen image plane, which is the panel's plane at the clear threshold, so thresholds other than 90° stay consistent. It defaults to a seated centered viewer — 1.3 screen heights above the hinge, 1.6 out (~50 cm); the **Assume centered** button opts into that nominal pose explicitly. Clicking Calibrate freezes the viewer's position in 3D space: the camera runs for about a second (≤5 Vision face detections, Vision's `VNDetectFaceLandmarksRequest`), `FaceGeometry.estimate` converts each detection into a camera-frame pose (distance from the known face width, angular offsets from the eye landmarks rather than the face-box centre, which sits near the nose), and `FaceGeometry.worldEye` rotates it into the world frame using the live lid angle for that frame — compensating for the camera riding in the lid — before averaging and persisting (`eyeX`/`eyeY`/`eyeZ`). The frozen world pose then drives every fold until the next click; the camera is off at all other times. An opt-in setting (off by default) re-measures once per open session: ten seconds after the lid is reopened past 75° while still open, it runs the same one-shot measurement. macOS does not expose the camera field of view, so distance assumes a typical FaceTime-camera lens (70°); the angular offsets are measured. Frames stay in memory and are discarded.

The sensor reports whole degrees, so the raw angle is anti-aliased in two stages before it reaches the pixels: a rate-independent exponential filter smooths the quantized readings (120 ms time constant, snapping on jumps larger than 45°), leads the smoothed angle by the measured angular rate (60 ms of look-ahead, capped at the newest reading so a step cannot overshoot), and the renderer interpolates blur, perspective and dimming toward the filtered targets on its frame clock with a 30 ms time constant — well under the angle filter's 120 ms, so the presentation adds little lag of its own. The sensor is polled at 120 Hz. Screen frames are captured at the panel's full refresh rate (120 Hz on ProMotion, clamped elsewhere) and presented at the same rate, so live content and the fold both move in step with the display.

The first fold is kept seamless by arming: while the lid is within 15° above the clear threshold, the capture stream and overlay window already run with the window fully transparent, so crossing the threshold reveals live frames instead of waiting 100–300 ms for a cold capture and popping in at full fold strength. The reveal is instant — the overlay is opaque from its first visible frame (the rendered image carries an opaque black backdrop, verified pixel-by-pixel), because any window transparency would show the live screen through the effect — and the fold itself starts from rest through the two-degree rotation ease described above. Opening past the threshold still hides the overlay immediately; the capture tears down after 2 s away from the threshold so hovering near the fold point does not keep the stream running.

- `./scripts/render-check.sh` writes `docs/effect-preview.png`, validating the
  image pipeline on synthetic frames without reading screen content.
- `./scripts/settings-render.sh` renders the settings window offscreen in both
  languages to `.build/settings-en.png` and `.build/settings-zh.png` as a
  layout and translation check; no screen capture or permission is involved.
  Controls come out untinted because only a key window in an active app gets
  the accent colour, so `docs/settings-*.png` are real screenshots of the app.
- `./scripts/make-icon.sh` regenerates `Resources/AppIcon.icns` from
  `Resources/AppIcon.png`; replace that 1024×1024 image to change the icon.

## Performance check

`./scripts/benchmark.sh` compares the old bitmap output against the Metal output
on a 3024×1964 synthetic frame. First local measurements were medians of about
12.9ms and 4.7ms respectively, which is not an end-to-end frame rate.
`./scripts/metal-check.sh` verifies actual texture orientation. The core tests
cover both time-based interpolation and instant clearing at the threshold.

## Debug mode

Duo Effect is a menu bar app with no console, so a sudden exit otherwise leaves
nothing behind but a system crash report. Turn on **Start Debug Logging** in the
status item menu, or launch with `--debug`, and lifecycle events are written to
`~/Library/Logs/Duo Effect/debug.log` (also visible in Console.app under the
`local.ruixiang.macbookduo` subsystem). **Show Debug Log…** reveals the file.

The log records capture start and stop, renderer creation and release, effect
on/off transitions with the angle and threshold, sensor and permission changes,
sleep/wake suspensions, and errors. Per-frame output is deliberately omitted;
only anomalous frames are logged. The file rotates past 4 MB.

## References

- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor): sensor HID
  usage and feature-report protocol information.
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit):
  local screen capture excluding the app itself.
