//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-hitch open source project
//
// Copyright (c) 2026 the swift-hitch project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import HitchRecording

/// Frame pacing figures for one recording.
///
/// The terms follow Apple's: a hitch is a frame that arrives later than expected, hitch time
/// is how late it was, and the hitch time ratio is hitch time per second of recording.
///
/// The figures are measured where the app can see them, at the display link on the main
/// thread. They include every frame the main thread delivered late, and they do not include a
/// frame that the main thread delivered on time and the render server then presented late.
/// Instruments and MetricKit measure at the display instead, so their hitch time ratio for the
/// same session can differ. Use these figures to compare one build of an app with another, not
/// to compare with a figure from another tool.
public struct FrameStatistics: Equatable, Sendable {
  /// Apple's guidance for the hitch time ratio.
  public enum Rating: String, Sendable {
    /// Below 5 ms/s. Hitches are hardly noticed.
    case good
    /// From 5 to 10 ms/s. Some hitches are noticed.
    case warning
    /// Above 10 ms/s. Hitches get in the way.
    case critical
  }

  /// The recorded time in seconds.
  public var duration: Double
  public var frameCount: Int
  /// How many frames arrived late.
  public var hitchCount: Int
  /// The total lateness in milliseconds.
  public var hitchTime: Double
  /// Hitch time in milliseconds per second of recording.
  public var hitchTimeRatio: Double
  /// How many frames took longer than 100 ms.
  public var longFrameCount: Int
  /// Frame interval percentiles in milliseconds.
  public var p50: Double
  public var p95: Double
  public var max: Double
  /// The interval the display expected most of the time, in milliseconds: about 8.3 on a
  /// 120 Hz display and 16.7 on a 60 Hz one.
  public var typicalExpectedInterval: Double

  public var rating: Rating {
    if hitchTimeRatio < 5 { return .good }
    return hitchTimeRatio <= 10 ? .warning : .critical
  }

  /// A frame counts as a hitch when it is late by more than this share of the expected
  /// interval. Display link callbacks jitter by a fraction of a millisecond, and a dropped
  /// frame is late by a whole interval.
  static let latenessTolerance = 0.5
  static let longFrameThreshold = 100.0

  /// Computes the statistics, or returns `nil` when no frames were recorded.
  public init?(_ frames: Recording.Frames) {
    let intervals = frames.intervals
    guard !intervals.isEmpty else { return nil }

    let expectedIntervals = frames.expectedIntervals
    let fallback = Statistics.percentile(intervals, 0.5)
    var hitchCount = 0
    var hitchTime = 0.0
    var lastExpected = fallback
    for (index, interval) in intervals.enumerated() {
      if expectedIntervals[index] > 0 { lastExpected = expectedIntervals[index] }
      let lateness = interval - lastExpected
      if lateness > lastExpected * Self.latenessTolerance {
        hitchCount += 1
        hitchTime += lateness
      }
    }

    let duration = intervals.reduce(0, +) / 1000
    self.duration = duration
    self.frameCount = intervals.count
    self.hitchCount = hitchCount
    self.hitchTime = hitchTime
    self.hitchTimeRatio = duration > 0 ? hitchTime / duration : 0
    self.longFrameCount = intervals.filter { $0 > Self.longFrameThreshold }.count
    self.p50 = Statistics.percentile(intervals, 0.5)
    self.p95 = Statistics.percentile(intervals, 0.95)
    self.max = intervals.max() ?? 0
    let known = frames.expected.filter { $0.interval > 0 }
    self.typicalExpectedInterval = known.max { $0.count < $1.count }?.interval ?? fallback
  }
}

/// Figures for one series of durations.
public struct SampleStatistics: Equatable, Sendable {
  /// Durations that fall into two separate groups.
  ///
  /// A median or a 95th percentile describes one of the groups and hides the other. When half
  /// of the taps take 5 ms and the other half 350 ms, the two halves usually take different
  /// code paths, and the split is the finding.
  public struct Groups: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
      public var count: Int
      public var median: Double
      public var min: Double
      public var max: Double
    }

    public var lower: Group
    public var upper: Group
  }

  public var count: Int
  public var min: Double
  public var p50: Double
  public var p95: Double
  public var max: Double
  /// Set when the durations fall into two separate groups.
  public var groups: Groups?

  public init?(_ values: [Double]) {
    guard !values.isEmpty else { return nil }
    count = values.count
    min = values.min() ?? 0
    p50 = Statistics.percentile(values, 0.5)
    p95 = Statistics.percentile(values, 0.95)
    max = values.max() ?? 0
    groups = Statistics.groups(values)
  }
}

/// The figures of one recording.
public struct Summary: Equatable, Sendable {
  public var frames: FrameStatistics?
  /// Keyed by the label of each series: `name`, or `name[tag]`.
  public var samples: [String: SampleStatistics]
  /// Intervals that were begun and never ended, by name.
  public var unfinishedIntervals: [String: Int]

  public init(_ recording: Recording) {
    frames = FrameStatistics(recording.frames)
    var samples: [String: SampleStatistics] = [:]
    for series in recording.series {
      samples[series.label] = SampleStatistics(series.values)
    }
    self.samples = samples
    unfinishedIntervals = recording.unfinishedIntervals
  }

  /// Every figure as a flat table, keyed by names such as `hitchTimeRatio`, `image.load.p95`
  /// or `image.load[hit].p95`. Lower is better for all of them.
  public var metrics: [String: Double] {
    var metrics: [String: Double] = [:]
    if let frames {
      metrics["hitchTimeRatio"] = frames.hitchTimeRatio
      metrics["longFrameCount"] = Double(frames.longFrameCount)
      metrics["frame.p95"] = frames.p95
      metrics["frame.max"] = frames.max
    }
    for (name, statistics) in samples {
      metrics["\(name).p50"] = statistics.p50
      metrics["\(name).p95"] = statistics.p95
      metrics["\(name).max"] = statistics.max
    }
    return metrics
  }

  /// How many values stand behind each metric: the number of durations in a series. Frame
  /// metrics are left out.
  public var sampleCounts: [String: Int] {
    var counts: [String: Int] = [:]
    for (name, statistics) in samples {
      for suffix in ["p50", "p95", "max"] {
        counts["\(name).\(suffix)"] = statistics.count
      }
    }
    return counts
  }
}

public enum Statistics {
  /// The nearest-rank percentile. `fraction` runs from 0 to 1.
  public static func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = Int((fraction * Double(sorted.count)).rounded(.up))
    return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
  }

  /// The median, averaging the two middle values of an even count.
  public static func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2)
      ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }

  /// Splits the values at their widest gap and returns the two sides when they are clearly
  /// apart: each side holds at least a fifth of the values (and at least three), and the gap
  /// is more than twice as wide as either side.
  public static func groups(_ values: [Double]) -> SampleStatistics.Groups? {
    guard values.count >= 8 else { return nil }
    let sorted = values.sorted()
    var split = 0
    var widest = 0.0
    for index in 0..<(sorted.count - 1) where sorted[index + 1] - sorted[index] > widest {
      widest = sorted[index + 1] - sorted[index]
      split = index
    }
    let lower = Array(sorted[...split])
    let upper = Array(sorted[(split + 1)...])
    let smallest = Swift.max(3, Int((Double(sorted.count) * 0.2).rounded(.up)))
    guard lower.count >= smallest, upper.count >= smallest else { return nil }
    let spread = Swift.max(lower[lower.count - 1] - lower[0], upper[upper.count - 1] - upper[0])
    guard widest > 2 * spread else { return nil }

    func group(_ values: [Double]) -> SampleStatistics.Groups.Group {
      .init(
        count: values.count, median: median(values), min: values[0], max: values[values.count - 1])
    }
    return .init(lower: group(lower), upper: group(upper))
  }
}
