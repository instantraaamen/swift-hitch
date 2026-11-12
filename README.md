# swift-hitch

Measure hitches on a real device while a person uses the app, then compare before and after a change.

[日本語](README.ja.md)

The usual way to measure scrolling is an XCUITest with `XCTOSSignpostMetric` or the hitch metrics. Driving the app from a test turns accessibility on and reads the view hierarchy after every action, and that work lands on the main thread of the app being measured. The same scroll can measure many times worse when a test drives it than when a hand does.

`swift-hitch` takes the test runner out of the picture:

- **`Hitch`**, a small library. The app records its own frame intervals and any durations you name, and writes them to its Documents directory.
- **`hitch`**, a command line tool. It launches the app on a device with recording on, waits while you use it, pulls the recording off the device, and compares runs.

## Installation

```swift
.package(url: "https://github.com/instantraaamen/swift-hitch", from: "0.1.0")
```

Add the `Hitch` product to your app target.

## Recording

Start the recorder at launch. It does nothing unless the app was launched with `--hitch-record`:

```swift
import Hitch

@main
struct MyApp: App {
  init() {
    #if DEBUG
      Hitch.startIfRequested(metadata: ["commit": "abc123"])
    #endif
  }
}
```

Frame intervals are recorded from then on. Add your own durations where they matter:

```swift
let start = Hitch.now()
let image = await loader.image(for: item)
Hitch.sample("image.load", since: start)

let layout = Hitch.measure("list.layout") { computeLayout() }
```

To see how a tap feels, mark the top of its handler:

```swift
Button("Open") {
  Hitch.markInteraction("open.detail")
  open(item)
}
```

That records how long the touch waited for the handler, how long until the next frame, and the longest of the 30 frames after it.

Every call is a no-op until a recording starts. The recording is written every two seconds and when the app moves to the background, to `Documents/hitch/<UTC timestamp>.json`.

## Collecting

```sh
swift run hitch record --device <UDID> --bundle-id com.example.app --label before
```

The tool launches the app with `--hitch-record`, waits for you to press Return, copies the recording into `hitch-recordings/`, and prints its figures:

```
hitch-recordings/before-20261112-031500.json
  iPhone17,1, iOS 18.2.0, com.example.app 1.0 (1)
  hitch time ratio  6.2 ms/s (warning) over 61.2 s, 7310 frames
  hitches           41, frames over 100 ms: 0
  frame interval    p50 8.3 ms, p95 8.5 ms, max 58.1 ms

  sample      count  p50   p95   max
  image.load    412  3.1  11.8  40.2
```

Use `--simulator booted` to try the flow on a simulator. Simulator figures say little about a device.

## Comparing

One run is noisy. Record each side a few times, handling the app the same way, and compare medians:

```sh
swift run hitch compare \
  --before hitch-recordings/before-*.json \
  --after hitch-recordings/after-*.json \
  --goals goals.json
```

```
median of 3 run(s) before, 3 run(s) after
metric          before  after  change  noise    verdict
frame.max         65.0   34.2   -30.8    0.2   improved
hitchTimeRatio     138    9.4  -128.5    5.5   improved
image.load.p95    14.2    7.2    -7.1    0.5   improved
goal missed: hitchTimeRatio is 9.4, limit 5.0
```

A change is reported only when it is larger than the spread among the "before" runs and larger than 1% of the "before" value. `goals.json` holds upper limits, checked against the "after" medians:

```json
{ "hitchTimeRatio": 5, "image.load.p95": 16 }
```

The command exits with a failure when a goal is missed, or with `--fail-on-regression` when a metric regressed.

## What the numbers mean

The terms are Apple's. A hitch is a frame that arrives later than the display expected, hitch time is how late, and the hitch time ratio is hitch time per second: below 5 ms/s is good, 5 to 10 is noticeable, above 10 is in the way.

Frames are observed with a `CADisplayLink` on the main run loop, so a hitch here means the main thread was busy when the display asked for a frame. A frame that was late on the render server alone is not seen; use Instruments for that. A frame counts as a hitch when it is more than half an interval late.

## License

MIT. See [LICENSE](LICENSE).
