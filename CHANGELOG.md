# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-13

### Added

- `Hitch`, an in-app recorder of display link intervals and named durations.
- `HitchSignposter`, which emits signposts and records the same intervals.
- Tags, to keep apart durations that share a name but are not comparable.
- A count of intervals that were begun and never ended.
- `Hitch.markInteraction`, which measures from a touch to its handler and the frames that follow, over a window of time.
- The conditions of a recording: display refresh rate, build configuration, thermal state, Low Power Mode and battery state.
- `hitch record`, which launches the app, collects the recording and stores the label and git commit with it.
- `hitch report` and `hitch compare`, with medians across runs, a noise threshold, goals, and a check that the recordings are comparable.
- Detection of durations that fall into two groups.
- Separate products for the recorder (`Hitch`), the file format (`HitchRecording`) and the analysis (`HitchAnalysis`).

[Unreleased]: https://github.com/instantraaamen/swift-hitch/compare/0.1.0...HEAD
[0.1.0]: https://github.com/instantraaamen/swift-hitch/releases/tag/0.1.0
