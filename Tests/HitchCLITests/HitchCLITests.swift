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
import HitchAnalysis
import HitchRecording
import Testing

@testable import HitchCLI

private func makeRecording(
  series: [Recording.Series] = [],
  metadata: [String: String] = [:],
  unfinishedIntervals: [String: Int] = [:],
  configuration: Recording.App.Configuration = .release
) -> Recording {
  var frames = Recording.Frames()
  for _ in 0..<100 { frames.append(interval: 8.3, expected: 8.3) }
  let conditions = Recording.Conditions(
    thermalState: .nominal, isLowPowerModeEnabled: false, batteryState: .unplugged)
  return Recording(
    startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1),
    device: .init(
      model: "iPhone17,1", systemName: "iOS", systemVersion: "18.2.0", maximumFramesPerSecond: 120),
    app: .init(
      bundleIdentifier: "com.example.app", version: "1.0", build: "7", configuration: configuration),
    conditionsAtStart: conditions, conditionsAtEnd: conditions,
    metadata: metadata, frames: frames, series: series, unfinishedIntervals: unfinishedIntervals)
}

@Suite struct ReportTests {
  @Test func showsWhereAndHowTheRecordingWasMade() {
    let report = Format.report(makeRecording(metadata: ["commit": "abc123"]), title: "run.json")
    #expect(report.contains("iPhone17,1, iOS 18.2.0, up to 120 Hz"))
    #expect(report.contains("com.example.app 1.0 (7), release build"))
    #expect(report.contains("thermal nominal, unplugged"))
    #expect(report.contains("commit: abc123"))
    #expect(report.contains("expected 8.3 ms"))
    #expect(!report.contains("note:"))
  }

  @Test func pointsOutTwoGroupsUnfinishedIntervalsAndDebugBuilds() {
    let values: [Double] = [1, 3, 5, 7, 9, 11, 13, 352, 355, 357, 360, 363, 353, 356]
    let report = Format.report(
      makeRecording(
        series: [.init(name: "tap.touchUpToHandler", values: values)],
        unfinishedIntervals: ["image.final": 3],
        configuration: .debug),
      title: "run.json")
    #expect(
      report.contains(
        "note: tap.touchUpToHandler falls into two groups: 7 around 7.0 ms and 7 around 356 ms."))
    #expect(report.contains("note: 3 interval(s) of image.final were begun and never ended"))
    #expect(report.contains("note: Recorded from a debug build."))
  }
}

@Suite struct GoalCheckTests {
  private let summaries = [
    Summary(makeRecording(series: [.init(name: "image.load", tag: "hit", values: [4, 5, 30])]))
  ]

  @Test func passesWhenEveryGoalIsMet() {
    let check = GoalCheck(goals: Goals(limits: ["hitchTimeRatio": 5]), summaries: summaries)
    #expect(check.lines == ["all 1 goal(s) met"])
    #expect(!check.failed(strict: true))
  }

  @Test func failsOnAMissedGoalAndNotesFewValues() {
    let check = GoalCheck(goals: Goals(limits: ["image.load[hit].p95": 16]), summaries: summaries)
    #expect(check.lines.contains("goal missed: image.load[hit].p95 is 30.0, limit 16.0"))
    #expect(
      check.lines.contains("note: image.load[hit].p95 rests on 3 value(s) in the shortest run."))
    #expect(check.failed(strict: false))
  }

  @Test func anUncheckedGoalOnlyFailsWhenStrict() {
    let check = GoalCheck(goals: Goals(limits: ["image.decode.p95": 8]), summaries: summaries)
    #expect(check.lines.count == 1)
    #expect(
      check.lines[0].hasPrefix("goal not checked: nothing was recorded for image.decode.p95."))
    #expect(!check.failed(strict: false))
    #expect(check.failed(strict: true))
  }
}

@Suite struct RecordTests {
  /// Older recordings stay on the device. The one to collect is found by the identifier that
  /// was passed at launch, not by being the newest file.
  @Test func picksTheRecordingOfThisRun() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "hitch-cli-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makeRecording(metadata: ["run": "wanted"]).encoded()
      .write(to: directory.appendingPathComponent("20260101-000000-000.json"))
    try makeRecording(metadata: ["run": "newer"]).encoded()
      .write(to: directory.appendingPathComponent("20260102-000000-000.json"))
    try Data("not json".utf8).write(
      to: directory.appendingPathComponent("20260103-000000-000.json"))

    let found = try #require(Record.recording(ofRun: "wanted", in: directory))
    #expect(found.0.lastPathComponent == "20260101-000000-000.json")
    #expect(Record.recording(ofRun: "missing", in: directory) == nil)
  }

  @Test func comparisonCanListEveryRun() {
    let before = [10.0, 300, 320].map { stall -> Summary in
      var recording = makeRecording()
      recording.frames.append(interval: stall, expected: 8.3)
      return Summary(recording)
    }
    let text = Format.comparison(
      Comparison(before: before, after: before), beforeRuns: 3, afterRuns: 3, showRuns: true)
    #expect(text.contains("runs"))
    #expect(text.contains(" -> "))
  }
}
