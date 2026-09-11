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

The bottom hinge and picture height stay fixed. Closing progressively narrows the top edge using the original taper curve, without the old vertical shrink-then-stretch. Perspective strength blends from flat to full taper. Smoothstep closing progress fades the image to black and increases blur. At the clear threshold the overlay is removed immediately. A spatial mask varies blur continuously from 5% of the current maximum radius at the hinge to 100% at the camera edge using CIMaskedVariableBlur. Metal presentation remains at 60 fps.

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
