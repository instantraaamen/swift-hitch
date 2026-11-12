# Measuring on a device

Get figures that you can compare from one build to the next.

## Overview

A measurement is only worth as much as the conditions it was taken under. These are the ways a
figure goes wrong, and what the recorder and the tool do about each.

### Let a person drive

A UI test turns accessibility on and reads the view hierarchy after every action. That work
runs on the main thread of the app, so a scroll driven by a test can measure many times worse
than the same scroll driven by hand. Launch the app with `hitch record` and use it yourself.

### Measure on a device, with real data

The simulator runs on the Mac's hardware. A problem that grows with the amount of data, such as
work done per item on every frame, does not show with the few dozen items of a test fixture.
Record on a device that holds a realistic amount of data, and store that amount with the
recording so that two recordings with different amounts are not compared by accident:

```swift
Hitch.startIfRequested(metadata: ["itemCount": "\(store.count)"])
```

### Keep the conditions the same

A hot device and a device in Low Power Mode run slower. A display that drops to a lower refresh
rate has a longer frame interval. A debug build is not optimized. The recording stores all of
these, and `hitch compare` warns when two recordings differ in any of them.

### Record more than once

One run is noisy. Record each side of a comparison at least three times and compare medians.
`hitch compare` only reports a change that is larger than the spread among the runs made before
the change.

### Keep unlike durations apart

A cache hit and a cache miss share a name and nothing else. Give them a tag, and each gets its
own figures:

```swift
signposter.endInterval("image.load", state, tag: wasCached ? "hit" : "miss")
```

When durations under one name still fall into two separate groups, the report says so. That
usually means two code paths, and a median describes only one of them.

### End every interval

An interval that is begun and not ended on some code path drops out of the figures without a
trace. The recorder counts intervals that never ended, and the report lists them.
