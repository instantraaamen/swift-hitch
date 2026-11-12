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

import ArgumentParser
import Foundation
import HitchAnalysis
import HitchRecording

@main
struct HitchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hitch",
    abstract: "Record frame pacing on a device by hand, then compare before and after.",
    version: "0.1.0",
    subcommands: [Record.self, Report.self, Compare.self]
  )
}

struct Report: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print the figures of one or more recordings.")

  @Argument(help: "Recording files.", completion: .file(extensions: ["json"]))
  var recordings: [String]

  @Option(name: .long, help: "A JSON file of upper limits, such as {\"hitchTimeRatio\": 5}.")
  var goals: String?

  @Flag(name: .long, help: "Also fail when a goal has no figure to check.")
  var strict = false

  func run() throws {
    let loaded = try recordings.map { try Recording.load(from: URL(fileURLWithPath: $0)) }
    for (path, recording) in zip(recordings, loaded) {
      print(Format.report(recording, title: path))
    }
    guard let goals else { return }
    let summaries = loaded.map(Summary.init)
    let outcome = GoalCheck(
      goals: try Goals.load(from: URL(fileURLWithPath: goals)), summaries: summaries)
    outcome.lines.forEach { print($0) }
    if outcome.failed(strict: strict) { throw ExitCode.failure }
  }
}

struct Compare: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Compare the median of several runs before and after a change.",
    discussion: """
      Record each side several times; three runs each is a good start. A change counts only \
      when it is larger than the spread among the "before" runs, so record the "before" side \
      more often when the result is close.
      """
  )

  @Option(name: .long, parsing: .upToNextOption, help: "Recordings made before the change.")
  var before: [String]

  @Option(name: .long, parsing: .upToNextOption, help: "Recordings made after the change.")
  var after: [String]

  @Option(name: .long, help: "A JSON file of upper limits, such as {\"hitchTimeRatio\": 5}.")
  var goals: String?

  @Flag(name: .long, help: "Exit with a failure when a metric regressed.")
  var failOnRegression = false

  @Flag(name: .long, help: "Print the figure of every run next to the medians.")
  var showRuns = false

  @Flag(
    name: .long,
    help: "Also fail when the recordings are not comparable or a goal has no figure to check.")
  var strict = false

  func validate() throws {
    guard !before.isEmpty, !after.isEmpty else {
      throw ValidationError("Pass at least one recording to both --before and --after.")
    }
  }

  func run() throws {
    let beforeRecordings = try before.map { try Recording.load(from: URL(fileURLWithPath: $0)) }
    let afterRecordings = try after.map { try Recording.load(from: URL(fileURLWithPath: $0)) }
    let beforeSummaries = beforeRecordings.map(Summary.init)
    let afterSummaries = afterRecordings.map(Summary.init)

    let issues = Comparability.issues(among: beforeRecordings + afterRecordings)
    for issue in issues {
      print("warning: not comparable: \(issue)")
    }
    for caution in Comparability.cautions(about: beforeRecordings + afterRecordings) {
      print("note: \(caution)")
    }

    let comparison = Comparison(before: beforeSummaries, after: afterSummaries)
    print(
      Format.comparison(
        comparison, beforeRuns: before.count, afterRuns: after.count, showRuns: showRuns))

    var failed = strict && !issues.isEmpty
    if let goals {
      let outcome = GoalCheck(
        goals: try Goals.load(from: URL(fileURLWithPath: goals)), summaries: afterSummaries)
      outcome.lines.forEach { print($0) }
      failed = failed || outcome.failed(strict: strict)
    }
    if failOnRegression, comparison.metrics.contains(where: { $0.verdict == .regressed }) {
      failed = true
    }
    if failed { throw ExitCode.failure }
  }
}

/// Goals checked against the median of some runs, as lines to print.
struct GoalCheck {
  /// Below this many durations a percentile says little.
  static let fewValues = 5

  var violations: [Goals.Violation]
  var unchecked: [String]
  var lines: [String] = []

  init(goals: Goals, summaries: [Summary]) {
    let medians = Goals.medians(of: summaries)
    violations = goals.violations(in: medians)
    unchecked = goals.unchecked(in: medians)

    for violation in violations {
      lines.append(
        "goal missed: \(violation.name) is \(Format.number(violation.actual)), limit \(Format.number(violation.limit))"
      )
    }
    for name in unchecked {
      lines.append(
        "goal not checked: nothing was recorded for \(name). Check the name, and that the session reached it."
      )
    }
    for name in goals.limits.keys.sorted() where medians[name] != nil {
      let counts = summaries.compactMap { $0.sampleCounts[name] }
      if let fewest = counts.min(), fewest < Self.fewValues {
        lines.append("note: \(name) rests on \(fewest) value(s) in the shortest run.")
      }
    }
    if violations.isEmpty, unchecked.isEmpty {
      lines.append("all \(goals.limits.count) goal(s) met")
    }
  }

  func failed(strict: Bool) -> Bool {
    !violations.isEmpty || (strict && !unchecked.isEmpty)
  }
}

enum Format {
  static func number(_ value: Double) -> String {
    String(format: value >= 100 ? "%.0f" : "%.1f", value)
  }

  /// A signed number, without a sign when it rounds to zero.
  static func change(_ delta: Double) -> String {
    let magnitude = number(abs(delta))
    guard magnitude.contains(where: { $0 != "0" && $0 != "." }) else { return magnitude }
    return (delta > 0 ? "+" : "-") + magnitude
  }

  static func conditions(_ conditions: Recording.Conditions) -> String {
    var parts = ["thermal \(conditions.thermalState.rawValue)"]
    if conditions.isLowPowerModeEnabled { parts.append("Low Power Mode") }
    if let battery = conditions.batteryState { parts.append(battery.rawValue) }
    return parts.joined(separator: ", ")
  }

  static func report(_ recording: Recording, title: String) -> String {
    let summary = Summary(recording)
    let refreshRate = recording.device.maximumFramesPerSecond.map { ", up to \($0) Hz" } ?? ""
    var lines = [
      title,
      "  \(recording.device.model), \(recording.device.systemName) \(recording.device.systemVersion)\(refreshRate)",
      "  \(recording.app.bundleIdentifier) \(recording.app.version) (\(recording.app.build)), "
        + "\(recording.app.configuration.rawValue) build",
    ]
    if recording.conditionsAtStart == recording.conditionsAtEnd {
      lines.append("  \(conditions(recording.conditionsAtStart))")
    } else {
      lines.append(
        "  \(conditions(recording.conditionsAtStart)) at the start, "
          + "\(conditions(recording.conditionsAtEnd)) at the end")
    }
    // The run identifier only serves to find the file after a launch.
    for (key, value) in recording.metadata.sorted(by: { $0.key < $1.key }) where key != "run" {
      lines.append("  \(key): \(value)")
    }
    for caution in Comparability.cautions(about: [recording]) {
      lines.append("  note: \(caution)")
    }
    if let frames = summary.frames {
      lines.append(
        "  hitch time ratio  \(number(frames.hitchTimeRatio)) ms/s (\(frames.rating.rawValue))"
          + " over \(number(frames.duration)) s, \(frames.frameCount) frames"
      )
      lines.append(
        "  hitches           \(frames.hitchCount), frames over 100 ms: \(frames.longFrameCount)"
      )
      lines.append(
        "  frame interval    p50 \(number(frames.p50)) ms, p95 \(number(frames.p95)) ms, "
          + "max \(number(frames.max)) ms, expected \(number(frames.typicalExpectedInterval)) ms"
      )
    } else {
      lines.append("  no frames recorded")
    }
    let samples = summary.samples.sorted { $0.key < $1.key }
    let rows = samples.map { name, statistics in
      [
        name, "\(statistics.count)", number(statistics.min), number(statistics.p50),
        number(statistics.p95),
        number(statistics.max),
      ]
    }
    if !rows.isEmpty {
      lines.append("")
      lines += table(header: ["sample", "count", "min", "p50", "p95", "max"], rows: rows).map {
        "  \($0)"
      }
    }
    for (name, statistics) in samples {
      guard let groups = statistics.groups else { continue }
      lines.append(
        "  note: \(name) falls into two groups: \(groups.lower.count) around \(number(groups.lower.median)) ms "
          + "and \(groups.upper.count) around \(number(groups.upper.median)) ms. "
          + "The percentiles above describe neither.")
    }
    for (name, count) in summary.unfinishedIntervals.sorted(by: { $0.key < $1.key }) {
      lines.append(
        "  note: \(count) interval(s) of \(name) were begun and never ended, and are not counted.")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  static func comparison(_ comparison: Comparison, beforeRuns: Int, afterRuns: Int, showRuns: Bool)
    -> String
  {
    func runs(_ values: [Double]) -> String { values.map(number).joined(separator: " ") }
    let rows = comparison.metrics.map { metric in
      [
        metric.name,
        number(metric.before),
        number(metric.after),
        change(metric.delta),
        number(metric.noise),
        metric.verdict.rawValue,
      ] + (showRuns ? ["\(runs(metric.beforeRuns)) -> \(runs(metric.afterRuns))"] : [])
    }
    var lines = ["median of \(beforeRuns) run(s) before, \(afterRuns) run(s) after"]
    lines += table(
      header: ["metric", "before", "after", "change", "noise", "verdict"]
        + (showRuns ? ["runs"] : []),
      rows: rows,
      leftAligned: showRuns ? [0, 6] : [0])
    if beforeRuns < 2 {
      lines.append(
        "note: with one run before the change, noise is unknown and every difference counts.")
    }
    return lines.joined(separator: "\n")
  }

  /// - Parameter leftAligned: The columns that hold text. The others hold numbers and are
  ///   right-aligned.
  static func table(header: [String], rows: [[String]], leftAligned: Set<Int> = [0]) -> [String] {
    let all = [header] + rows
    let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
    return all.map { row in
      row.enumerated().map { column, cell in
        let padding = String(repeating: " ", count: widths[column] - cell.count)
        return leftAligned.contains(column) ? cell + padding : padding + cell
      }
      .joined(separator: "  ")
      .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }
  }
}
