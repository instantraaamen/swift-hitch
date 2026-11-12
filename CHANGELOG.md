# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Hitch`, an in-app recorder for frame intervals, named durations and touch-to-frame timings.
- `hitch record` to launch an app on a device or simulator and collect its recording.
- `hitch report` to print the hitch time ratio and sample percentiles of a recording.
- `hitch compare` to compare the median of several runs before and after a change, with optional goals.
