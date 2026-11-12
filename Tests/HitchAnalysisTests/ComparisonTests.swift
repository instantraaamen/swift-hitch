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

@Suite struct ComparisonTests {
  private func summary(stall: Double) -> Summary {
    Summary(makeRecording(intervals: Array(repeating: 10.0, count: 99) + [stall]))
  }

  @Test func changeLargerThanNoiseCounts() throws {
    let comparison = Comparison(
      before: [summary(stall: 300), summary(stall: 310), summary(stall: 320)],
      after: [summary(stall: 100), summary(stall: 110), summary(stall: 90)]
    )
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .improved)
    #expect(ratio.after < ratio.before)
    #expect(ratio.noise > 0)
    #expect(ratio.beforeRuns.count == 3)
    #expect(ratio.afterRuns.count == 3)
  }

  @Test func changeWithinNoiseIsUnchanged() throws {
    let comparison = Comparison(
      before: [summary(stall: 100), summary(stall: 300)],
      after: [summary(stall: 220)]
    )
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .unchanged)
  }

  @Test func regressionIsReported() throws {
    let comparison = Comparison(before: [summary(stall: 20)], after: [summary(stall: 400)])
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .regressed)
  }
}

@Suite struct GoalsTests {
  private let summary = Summary(
    makeRecording(
      intervals: Array(repeating: 10.0, count: 99) + [300],
      series: [.init(name: "image.load", tag: "hit", values: [4, 5, 6])]))

  @Test func reportsWhatIsExceeded() {
    let goals = Goals(limits: ["hitchTimeRatio": 5, "frame.max": 500, "image.load[hit].p95": 16])
    let violations = goals.violations(in: Goals.medians(of: [summary, summary]))
    #expect(violations.map(\.name) == ["hitchTimeRatio"])
  }

  /// A goal whose name matches nothing was not met; it was never looked at. A renamed series
  /// used to make its goal pass silently.
  @Test func reportsGoalsThatHaveNothingToCheck() {
    let goals = Goals(limits: [
      "hitchTimeRatio": 500, "image.load|hit.p95": 16, "image.decode.p95": 8,
    ])
    let medians = Goals.medians(of: [summary])
    #expect(goals.violations(in: medians).isEmpty)
    #expect(goals.unchecked(in: medians) == ["image.decode.p95", "image.load|hit.p95"])
  }
}

/// Each of these once made a before/after comparison meaningless without anyone noticing.
@Suite struct ComparabilityTests {
  private let frames = Array(repeating: 10.0, count: 500)

  @Test func identicalConditionsAreComparable() {
    let runs = [makeRecording(intervals: frames), makeRecording(intervals: frames)]
    #expect(Comparability.issues(among: runs).isEmpty)
    #expect(Comparability.cautions(about: runs).isEmpty)
  }

  @Test func differentDevicesAreNot() {
    let issues = Comparability.issues(among: [
      makeRecording(intervals: frames, model: "iPhone13,4"),
      makeRecording(intervals: frames, model: "iPhone17,1"),
    ])
    #expect(issues == ["The device differs: iPhone13,4, iPhone17,1."])
  }

  @Test func differentRefreshRatesAreNot() {
    let issues = Comparability.issues(among: [
      makeRecording(
        intervals: Array(repeating: 8.3, count: 500), expected: 8.3, maximumFramesPerSecond: 120),
      makeRecording(
        intervals: Array(repeating: 16.7, count: 250), expected: 16.7, maximumFramesPerSecond: 120),
    ])
    #expect(issues == ["The frame interval the display ran at differs: 8.3 ms, 16.7 ms."])
  }

  @Test func aDebugBuildAgainstAReleaseBuildIsNot() {
    let runs = [
      makeRecording(intervals: frames, configuration: .debug),
      makeRecording(intervals: frames, configuration: .release),
    ]
    #expect(
      Comparability.issues(among: runs) == ["The build configuration differs: debug, release."])
    #expect(Comparability.cautions(about: runs).count == 1)
  }

  @Test func aHotOrPowerSavingDeviceIsNot() {
    let issues = Comparability.issues(among: [
      makeRecording(intervals: frames),
      makeRecording(intervals: frames, thermalState: .serious, isLowPowerModeEnabled: true),
    ])
    #expect(issues.count == 2)
    #expect(issues.contains("Low Power Mode differs: off, on."))
    #expect(issues.contains { $0.hasPrefix("1 of 2 recordings were made on a hot device") })
  }

  /// A problem that only shows with thousands of items is invisible with a few dozen.
  @Test func differentAmountsOfDataAreNot() {
    let issues = Comparability.issues(among: [
      makeRecording(
        intervals: frames, metadata: ["itemCount": "45", "label": "before", "commit": "a1"]),
      makeRecording(
        intervals: frames, metadata: ["itemCount": "11837", "label": "after", "commit": "b2"]),
    ])
    #expect(issues == ["The metadata value `itemCount` differs: 45, 11837."])
  }

  @Test func veryDifferentLengthsAreNot() {
    let issues = Comparability.issues(among: [
      makeRecording(intervals: Array(repeating: 10.0, count: 500)),
      makeRecording(intervals: Array(repeating: 10.0, count: 3000)),
    ])
    #expect(issues.count == 1)
    #expect(issues[0].hasPrefix("The recordings differ in length, from 5 s to 30 s."))
  }

  @Test func theSimulatorIsCalledOut() {
    let cautions = Comparability.cautions(about: [makeRecording(model: "iPhone17,1 (Simulator)")])
    #expect(cautions.count == 1)
  }
}

@Suite struct RecordingFormatTests {
  @Test func survivesARoundTrip() throws {
    let original = makeRecording(
      intervals: [10, 20],
      series: [.init(name: "a", tag: "x", values: [1.5])],
      metadata: ["commit": "abc123"],
      unfinishedIntervals: ["a": 2])
    #expect(try Recording.decode(original.encoded()) == original)
  }

  @Test func refusesAnotherFormatVersion() throws {
    let old = Data(#"{"version": 1, "samples": {}}"#.utf8)
    #expect(throws: Recording.UnsupportedVersion(version: 1)) { try Recording.decode(old) }
  }

  @Test func labelsCombineNameAndTag() {
    #expect(Recording.Series(name: "image.load", values: []).label == "image.load")
    #expect(Recording.Series(name: "image.load", tag: "hit", values: []).label == "image.load[hit]")
  }
}
