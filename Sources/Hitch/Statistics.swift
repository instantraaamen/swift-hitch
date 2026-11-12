import Foundation

/// Frame pacing figures for one recording.
///
/// The terms follow Apple's: a hitch is a frame that arrives later than expected, hitch time
/// is how late it was, and the hitch time ratio is hitch time per second of recording.
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

    var hitchCount = 0
    var hitchTime = 0.0
    var lastExpected = Statistics.percentile(intervals, 0.5)
    for (index, interval) in intervals.enumerated() {
      if index < frames.expected.count, frames.expected[index] > 0 {
        lastExpected = frames.expected[index]
      }
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
  }
}

/// Figures for one named duration.
public struct SampleStatistics: Equatable, Sendable {
  public var count: Int
  public var p50: Double
  public var p95: Double
  public var max: Double

  public init?(_ values: [Double]) {
    guard !values.isEmpty else { return nil }
    count = values.count
    p50 = Statistics.percentile(values, 0.5)
    p95 = Statistics.percentile(values, 0.95)
    max = values.max() ?? 0
  }
}

/// The figures of one recording.
public struct Summary: Equatable, Sendable {
  public var frames: FrameStatistics?
  public var samples: [String: SampleStatistics]

  public init(_ recording: Recording) {
    frames = FrameStatistics(recording.frames)
    samples = recording.samples.compactMapValues(SampleStatistics.init)
  }

  /// Every figure as a flat table, keyed by names such as `hitchTimeRatio` or
  /// `image.load.p95`. Lower is better for all of them.
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
    }
    return metrics
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
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
  }
}
