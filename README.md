# swift-hitch

Measure hitches on a real device while a person uses the app, then compare before and after a change.

[日本語](README.ja.md)

The usual way to measure scrolling is a UI test with `XCTOSSignpostMetric` or the hitch metrics. Driving the app from a test turns accessibility on and reads the view hierarchy after every action, and that work lands on the main thread of the app being measured. The same scroll can measure many times worse when a test drives it than when a hand does.

`swift-hitch` takes the test runner out of the picture:

- **`Hitch`**, a small library. The app records its own frame intervals and any durations you name, and writes them to its Documents directory.
- **`hitch`**, a command line tool. It launches the app on a device with recording on, waits while you use it, pulls the recording off the device, and compares runs.

It complements Instruments. Reach for it when you want a number you can compare across builds, when a problem only shows with real data on a real device, or when Instruments cannot attach to the device at hand.

## Installation

```swift
.package(url: "https://github.com/instantraaamen/swift-hitch", from: "0.1.0")
```

Add the `Hitch` product to your app target. The package has no dependencies beyond [swift-argument-parser](https://github.com/apple/swift-argument-parser), which only the command line tool uses.

## Recording

Start the recorder at launch. It does nothing unless the app was launched with `--hitch-record`:

```swift
import Hitch

@main
struct MyApp: App {
  init() {
    #if DEBUG
      Hitch.startIfRequested(metadata: ["itemCount": "\(store.count)"])
    #endif
  }
}
```

Frame intervals are recorded from then on.

### Durations

If the app already uses `OSSignposter`, switch to `HitchSignposter`. It emits the same signposts, and while a recording runs it also stores the length of every interval under the signpost's name:

```swift
let signposter = HitchSignposter(subsystem: "com.example.app", category: "Images")

let state = signposter.beginInterval("image.load")
let image = try await loader.image(for: item)
signposter.endInterval("image.load", state, tag: image.wasCached ? "hit" : "miss")
```

A `tag` keeps apart durations that share a name but are not comparable. A cache hit and a cache miss get their own figures, `image.load[hit]` and `image.load[miss]`, instead of one average that describes neither.

An interval that is begun and never ended is counted and reported, so a code path that forgets to end it does not silently drop out of the figures.

Without signposts, `Hitch.measure("list.layout") { computeLayout() }` and `Hitch.sample(_:tag:milliseconds:)` do the same.

### Interactions

To see how a tap feels, mark the top of its handler:

```swift
Button("Open") {
  Hitch.markInteraction("open.detail")
  open(item)
}
```

That records how long the touch waited for the handler, how long until the next frame, and the longest frame in the 250 ms after it. The window is a length of time, not a number of frames, so the figure means the same at 60 Hz and at 120 Hz.

### What is stored

Every call is a no-op until a recording starts. The recording is written every two seconds and when the app moves to the background, to `Documents/hitch/<UTC timestamp>.json`, one file per launch.

Along with the measurements, the file holds what is needed to judge them later: the device model and system version, the display's refresh rate, whether the build was a debug build, the thermal state, Low Power Mode and battery state at the start and at the end, and the metadata you pass.

## Collecting

```sh
swift run hitch record --device <UDID> --bundle-id com.example.app --label before
```

The tool launches the app with `--hitch-record`, waits for you to press Return, copies the recording into `hitch-recordings/`, and prints its figures:

```
hitch-recordings/before-20261112-031500-000.json
  iPhone17,1, iOS 18.2.0, up to 120 Hz
  com.example.app 1.0 (1), release build
  thermal nominal, unplugged
  commit: 1f3c9aa
  label: before
  hitch time ratio  27.6 ms/s (critical) over 62.5 s, 7300 frames
  hitches           41, frames over 100 ms: 0
  frame interval    p50 8.3 ms, p95 8.5 ms, max 65.4 ms, expected 8.3 ms

  sample                        count   min   p50   p95   max
  image.load[hit]                 300   1.0   7.3  13.4  13.9
  image.load[miss]                 40  30.9  48.7  85.2  86.3
  open.detail.touchUpToHandler     18   3.1  11.3   364   364
  note: open.detail.touchUpToHandler falls into two groups: 9 around 6.7 ms and 9 around 359 ms. The percentiles above describe neither.
  note: 2 interval(s) of image.load were begun and never ended, and are not counted.
```

The two notes are the tool reading the recording for you. Durations that split into two groups usually take two code paths, and a median reports only one of them. Unfinished intervals mean the figure covers a subset.

`record` stores the label and the git commit of the current directory with the recording, and `--metadata key=value` adds more. Use `--simulator booted` to try the flow on a simulator; simulator figures say little about a device.

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
metric                            before  after  change  noise    verdict
frame.max                           65.1   33.8   -31.4    1.2   improved
frame.p95                            8.5    8.5     0.0    0.0  unchanged
hitchTimeRatio                      28.7    3.5   -25.1    1.7   improved
image.load[hit].p95                 13.4    6.7    -6.7    0.3   improved
image.load[miss].p95                85.2   83.3    -1.9    5.7  unchanged
open.detail.touchUpToHandler.p95     363   11.3  -352.0    1.1   improved
goal not checked: nothing was recorded for image.decode.p95. Check the name, and that the session reached it.
```

A change is reported only when it is larger than the spread among the "before" runs and larger than 1% of the "before" value. `--show-runs` prints the figure of every run next to the medians.

### Goals

`goals.json` holds upper limits, checked against the "after" medians:

```json
{ "hitchTimeRatio": 5, "image.load[hit].p95": 16 }
```

A goal that has nothing to check is reported instead of passing: a renamed series or a session that never reached a screen should not look like success. `hitch report --goals` checks goals against recordings without a comparison.

### Comparable conditions

Before comparing, the tool checks that the recordings were made under the same conditions, and warns when they were not:

```
warning: not comparable: The build configuration differs: debug, release.
warning: not comparable: The metadata value `itemCount` differs: 45, 11837.
```

It looks at the device, the system version, the build configuration, the refresh rate the display actually ran at, Low Power Mode, a hot device, the length of the recordings, and every metadata value you stored. Put anything that changes the workload into the metadata, such as how many items the app holds.

### Exit status

The command fails when a goal is missed, with `--fail-on-regression` when a metric regressed, and with `--strict` also when the recordings are not comparable or a goal has nothing to check.

## What the numbers mean

The terms are Apple's. A hitch is a frame that arrives later than the display expected, hitch time is how late, and the hitch time ratio is hitch time per second: below 5 ms/s is good, 5 to 10 is noticeable, above 10 is in the way.

The figures are measured where the app can see them, with a `CADisplayLink` on the main run loop. A hitch here means the main thread was busy when the display asked for a frame, and a frame counts when it is more than half an interval late. A frame that the main thread delivered on time and the render server presented late is not seen. Instruments and MetricKit measure at the display, so their hitch time ratio for the same session can differ. Use these figures to compare one build with another, not with a figure from another tool.

On an iPhone with a 120 Hz display, the display changes its refresh rate as it goes: in our runs it stayed at 60 Hz on a still screen and moved between 60, 80 and 120 Hz under a scroll. The recorder's display link follows it without asking for a rate of its own, and each frame is judged against the interval the display expected at that moment. The report shows the most common one as `expected`, and a comparison warns when two recordings ran at different intervals. Rates above 60 Hz are only available to an app whose Info.plist sets `CADisableMinimumFrameDurationOnPhone`.

A debug build is not optimized, and its durations are longer than what users see. The recording says which kind of build it came from, and the report points it out.

## Products

| Product | For | Contains |
|---|---|---|
| `Hitch` | the app | The recorder and `HitchSignposter`. |
| `HitchRecording` | tools | The recording file format. |
| `HitchAnalysis` | tools | Statistics, comparison, goals and the comparability checks. |
| `hitch` | the command line | `record`, `report` and `compare`. |

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
