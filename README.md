# Duo Effect

*[中文说明](README.zh-CN.md)*

A native macOS menu bar app that reads your MacBook's real lid angle and
applies perspective, dimming and blur to the built-in display as the lid closes.

## Running

Open `dist/Duo Effect.app`. The settings window appears on launch and the menu
bar shows the live angle.

0. The interface is English by default. The globe button in the top-left switches
   between English and 简体中文; the choice is saved automatically.
1. Click **Grant Screen Recording…** and allow **Duo Effect** in System Settings.
2. If macOS asks you to reopen the app, quit it and open it again.
3. Adjust **Clear threshold**, 90° by default. Closed is 0°; at or above the
   threshold the effect is removed.
4. Below the threshold, the threshold angle acts as the virtual reference plane:
   the image narrows and stretches around the bottom hinge while progressively
   dimming and blurring. The menu bar can pause or quit at any time.

Only the built-in display is affected, menu bar included. The settings window
stays readable, and the effect layer never intercepts the mouse, so the screen
remains fully usable. Normal lid-close sleep is preserved and settings are saved
automatically. The effect is removed whenever the sensor cannot be read, screen
capture fails, or the session sleeps or goes inactive.

## Requirements and caveats

- macOS 14 or newer, an Apple Silicon MacBook with a readable lid angle sensor.
- Verified on an M1 Pro MacBook Pro reading 112°; the app also shows live sensor
  status.
- Screen Recording permission drives the local live blur. Nothing is recorded to
  disk, no audio is captured, and nothing goes over the network.
- The lid angle HID protocol is not a documented Apple guarantee; future macOS
  releases may break compatibility.
- Signed with a local Apple Development certificate, not Developer ID notarized;
  this build targets the machine that produced it. Certificate-bound signing is
  what keeps an existing privacy grant valid across rebuilds.
- Protected video content may not be capturable by the system. This is a visual
  effect tool, not a privacy screen or a security boundary.

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
Screen Recording grant on every rebuild.

## Manual acceptance

With Screen Recording granted, check that: the image blurs progressively below
the threshold and is completely clear when reopened to it; the background keeps
updating while windows move and ordinary video plays; pause and quit restore
the original image; external displays stay untouched; and no effect lingers
after lock, sleep or wake.

## Effect model

The virtual viewpoint sits about 2.5 screen heights in front of the reference
plane; this is not eye tracking. The projected difference angle is capped at 75°
for extreme closed postures to avoid geometric flipping. Maximum dimming is 65%,
and gaussian blur strength is adjustable. Capture runs at native Retina
resolution and 60fps, with Core Image writing straight into a Metal display
texture. Perspective, dimming and blur are smoothed together over time, and
capture only runs while the effect is active.

- `./scripts/render-check.sh` writes `docs/effect-preview.png`, validating the
  image pipeline on synthetic frames without reading screen content.
- `./scripts/settings-render.sh` renders the settings window offscreen in both
  languages to `docs/settings-en.png` and `docs/settings-zh.png`. ImageRenderer
  cannot rasterize AppKit controls, so the language menu, the toggle and the
  sliders appear as placeholder bars.
- `./scripts/make-icon.sh` regenerates `Resources/AppIcon.icns` from
  `Resources/AppIcon.png`; replace that 1024×1024 image to change the icon.

## Performance check

`./scripts/benchmark.sh` compares the old bitmap output against the Metal output
on a 3024×1964 synthetic frame. First local measurements were medians of about
12.9ms and 4.7ms respectively, which is not an end-to-end frame rate.
`./scripts/metal-check.sh` verifies actual texture orientation. The core tests
cover both time-based interpolation and instant clearing at the threshold.

## If the permission never takes effect

Early ad-hoc signed builds can leave a stored grant that does not match the
current build. To migrate, quit the app, reset only this app's record, then
reopen and grant once in System Settings:

```sh
tccutil reset ScreenCapture local.ruixiang.macbookduo
```

Check the permission status shown in the app window. Running `--self-check`
directly from a terminal reports the permission state of the terminal that
launched it, which is not evidence that the GUI app is granted.

## References

- [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor): sensor HID
  usage and feature-report protocol information.
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit):
  local screen capture excluding the app itself.

The code is an independent implementation based on that interface information;
no external code or packages are vendored.

## License

[MIT](LICENSE). The app is not sandboxed: beyond the Screen Recording grant it
runs with your user's full file access and talks to IOKit HID directly, which is
what reading the lid angle requires.
