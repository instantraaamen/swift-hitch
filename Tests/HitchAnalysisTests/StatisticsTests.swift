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
import Testing

@testable import HitchAnalysis

@Suite struct StatisticsTests {
  @Test func percentileUsesNearestRank() {
    let values = (1...100).map(Double.init)
    #expect(Statistics.percentile(values, 0.5) == 50)
    #expect(Statistics.percentile(values, 0.95) == 95)
    #expect(Statistics.percentile([7], 0.95) == 7)
    #expect(Statistics.percentile([], 0.5) == 0)
  }

  @Test func medianAveragesTheMiddlePair() {
    #expect(Statistics.median([3, 1, 2]) == 2)
    #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
  }

  @Test func smoothFramesHaveNoHitches() throws {
    let frames = try #require(
      FrameStatistics(makeRecording(intervals: Array(repeating: 10.2, count: 100)).frames))
    #expect(frames.hitchCount == 0)
    #expect(frames.hitchTimeRatio == 0)
    #expect(frames.rating == .good)
    #expect(frames.typicalExpectedInterval == 10)
  }

  @Test func lateFramesAddUpToHitchTime() throws {
    // 98 frames on time, one dropped frame (10 ms late) and one long stall (190 ms late).
    let intervals = Array(repeating: 10.0, count: 98) + [20, 200]
    let frames = try #require(FrameStatistics(makeRecording(intervals: intervals).frames))
    #expect(frames.hitchCount == 2)
    #expect(frames.hitchTime == 200)
    #expect(frames.longFrameCount == 1)
    #expect(frames.max == 200)
    // 200 ms late over 1.2 s of recording.
    #expect(abs(frames.hitchTimeRatio - 200 / 1.2) < 0.001)
    #expect(frames.rating == .critical)
  }

  @Test func ratingFollowsApplesThresholds() throws {
    func rating(lateBy lateness: Double) throws -> FrameStatistics.Rating {
      // 99 frames of 10 ms and one late frame: close to one second of recording.
      let frames = Array(repeating: 10.0, count: 99) + [10 + lateness]
      return try #require(FrameStatistics(makeRecording(intervals: frames).frames)).rating
    }
    #expect(try rating(lateBy: 4) == .good)  // below the tolerance: not a hitch at all
    #expect(try rating(lateBy: 7) == .warning)
    #expect(try rating(lateBy: 30) == .critical)
  }

  @Test func expectedIntervalFollowsTheDisplay() throws {
    // A display that drops from 120 Hz to 60 Hz is not hitching.
    var frames = Recording.Frames()
    for interval in [8.3, 8.3, 8.3, 16.7, 16.7] {
      frames.append(interval: interval, expected: interval)
    }
    #expect(frames.expected == [.init(count: 3, interval: 8.3), .init(count: 2, interval: 16.7)])
    #expect(frames.expectedIntervals == [8.3, 8.3, 8.3, 16.7, 16.7])
    let statistics = try #require(FrameStatistics(frames))
    #expect(statistics.hitchCount == 0)
    #expect(statistics.typicalExpectedInterval == 8.3)
  }

  @Test func emptyRecordingHasNoFrameStatistics() {
    #expect(FrameStatistics(Recording.Frames()) == nil)
    #expect(Summary(makeRecording()).metrics.isEmpty)
  }

  @Test func summaryFlattensMetricsAndKeepsTagsApart() {
    let summary = Summary(
      makeRecording(
        intervals: [10, 10],
        series: [
          .init(name: "image.load", tag: "hit", values: [1, 2, 3]),
          .init(name: "image.load", tag: "miss", values: [40, 50, 60]),
          .init(name: "launch", values: [300]),
          .init(name: "empty", values: []),
        ]))
    #expect(summary.metrics["image.load[hit].p50"] == 2)
    #expect(summary.metrics["image.load[hit].p95"] == 3)
    #expect(summary.metrics["image.load[miss].p95"] == 60)
    #expect(summary.metrics["launch.max"] == 300)
    #expect(summary.metrics["hitchTimeRatio"] == 0)
    #expect(summary.metrics["empty.p50"] == nil)
    #expect(summary.sampleCounts["image.load[hit].p95"] == 3)
  }
}

/// A median hides a split: taps that take 5 ms half of the time and 350 ms the other half
/// have a median that depends on which half is one larger.
@Suite struct GroupsTests {
  @Test func findsTwoGroupsThatAreFarApart() throws {
    let fast: [Double] = [1, 3, 5, 7, 9, 11, 13, 2, 4, 6, 8, 10, 12, 5]
    let slow: [Double] = [352, 355, 357, 360, 363, 353, 356, 358, 361, 362, 354, 359, 357, 360]
    let groups = try #require(SampleStatistics(fast + slow)?.groups)
    #expect(groups.lower.count == 14)
    #expect(groups.upper.count == 14)
    #expect(groups.lower.max == 13)
    #expect(groups.upper.min == 352)
    #expect(groups.upper.median == 357.5)
  }

  @Test func findsGroupsThatAreCloserTogether() throws {
    let lower: [Double] = [130, 134, 138, 141, 136, 139]
    let upper: [Double] = [224, 231, 240, 248, 259, 236]
    let groups = try #require(SampleStatistics(lower + upper)?.groups)
    #expect(groups.lower.median == 137)
    #expect(groups.upper.min == 224)
  }

  @Test func leavesOneSpreadOutGroupAlone() {
    #expect(SampleStatistics((1...40).map(Double.init))?.groups == nil)
    #expect(SampleStatistics([10, 11, 12, 13, 14, 15, 16, 30])?.groups == nil)  // one outlier
    #expect(SampleStatistics([1, 1, 1, 400, 400, 400])?.groups == nil)  // too few to tell
    #expect(SampleStatistics(Array(repeating: 5, count: 20))?.groups == nil)
  }
}
