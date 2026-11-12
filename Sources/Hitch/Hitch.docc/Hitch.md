# ``Hitch``

Record frame pacing and durations inside an app while a person uses it.

## Overview

Driving an app from a UI test adds work to the main thread of the app being measured. `Hitch`
lets the app record itself instead: it watches the display link for late frames, stores the
durations you name, and writes everything to a file that the `hitch` command line tool collects
and compares.

Start the recorder at launch. It does nothing unless the app was launched with
``Hitch/Hitch/launchArgument``:

```swift
#if DEBUG
  Hitch.startIfRequested()
#endif
```

## Topics

### Recording

- ``Hitch/Hitch``
- <doc:MeasuringOnADevice>

### Measuring durations

- ``HitchSignposter``
