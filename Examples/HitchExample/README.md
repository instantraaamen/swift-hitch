# HitchExample

A list of 2000 rows, each with a picture that takes a few milliseconds to draw. It is here so that you can run `hitch record` and `hitch compare` from start to finish before putting `Hitch` into your own app.

The app has two ways of drawing the pictures:

- launched with `--slow`, it draws them on the main thread. Scrolling hitches.
- launched without it, it draws them in the background.

That gives a "before" and an "after" without building twice.

## Run it

Open `HitchExample.xcodeproj`, choose your team under Signing & Capabilities, and run the app on a device once so that it is installed. Then, from the root of this repository:

```sh
xcrun devicectl list devices   # shows the identifier of the device

swift run hitch record --device <UDID> --bundle-id com.example.HitchExample --label before -- --slow
swift run hitch record --device <UDID> --bundle-id com.example.HitchExample --label after
```

If you changed the bundle identifier to sign the app, pass that one. In each recording scroll the list the same way and open a few rows, then press Return in the terminal. Record each side three times, and compare:

```sh
swift run hitch compare \
  --before hitch-recordings/before-*.json \
  --after hitch-recordings/after-*.json
```

Without a device, `--simulator booted` in place of `--device <UDID>` runs the same flow. Simulator figures say little about a device.

## What to look for

- `hitchTimeRatio` and `frame.max` go down from "before" to "after".
- `thumbnail.load[miss]` may go *up*. In the background several pictures are drawn at once, and each takes longer than when they were drawn one after another. The scroll is smoother all the same, because that time is no longer spent on the main thread. A duration alone does not tell you how a screen feels; read it next to the frame figures.
- `open.detail.longestFrameAfter` shows the frame that drawing the large picture of the detail screen cost.

## Where the calls are

- `HitchExampleApp.swift` starts the recorder.
- `Pictures.swift` wraps the loading of a picture in a `HitchSignposter` interval, tagged `hit` or `miss`.
- `ItemList.swift` marks the tap that opens the detail screen.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml`, run `xcodegen generate` in this directory.
