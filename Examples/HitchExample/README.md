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

## What it showed

Three runs of each on an iPhone 18 Pro with iOS 27.2, a release build, about 30 seconds of scrolling and opening rows by hand:

```
median of 3 run(s) before, 3 run(s) after
metric                              before  after  change  noise    verdict
frame.max                              167   82.0   -84.6   18.2   improved
hitchTimeRatio                         130   30.0   -99.9   64.5   improved
open.detail.longestFrameAfter.p95      167   52.2    -114   18.2   improved
open.detail.touchUpToHandler.p95      31.3   28.7    -2.6    3.1  unchanged
thumbnail.load[miss].p50               4.8   26.6   +21.8    0.1  regressed
thumbnail.load[miss].p95               5.2    435    +430    1.7  regressed
```

- The hitch time ratio fell from 130 ms/s to 30 ms/s. On the main thread every picture cost the scroll about 5 ms, and a fast scroll asks for several in one frame.
- `thumbnail.load[miss]` went *up*, from 5 ms to hundreds at the 95th percentile. In the background many pictures are drawn at once and wait for each other. The scroll is smoother all the same, because that time is no longer spent on the main thread. A duration alone does not say how a screen feels; read it next to the frame figures.
- `open.detail.longestFrameAfter` fell from 167 ms to 52 ms: the large picture of the detail screen no longer holds up the frames of the transition. `touchUpToHandler` did not change, because nothing kept the tap waiting in either case.
- 30 ms/s is still far from good. Moving the drawing off the main thread removed one cause of the hitches in a fast scroll, not all of them.

The runs were made by hand and were not alike. One loaded 584 pictures and another 2292, which is why the noise of `hitchTimeRatio` is as large as 64.5. Your figures will differ; the direction should not. The display link ran at 60 Hz for about two thirds of the frames and at 80 Hz for the rest, mostly while the list was scrolling. It did not run at 120 Hz.

## Where the calls are

- `HitchExampleApp.swift` starts the recorder.
- `Pictures.swift` wraps the loading of a picture in a `HitchSignposter` interval, tagged `hit`, `miss`, or `joined` when it waited for a picture already being drawn.
- `ItemList.swift` marks the tap that opens the detail screen.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml`, run `xcodegen generate` in this directory.
