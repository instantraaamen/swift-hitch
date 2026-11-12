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

/// A before/after comparison of two sets of recordings.
///
/// One recording is noisy: thermal state, background work and the way the app was handled all
/// move the figures. Each side is therefore reduced to the median of its runs, and a change
/// only counts when it is larger than the spread already seen among the "before" runs and
/// larger than 1% of the "before" value.
public struct Comparison: Equatable, Sendable {
  public enum Verdict: String, Sendable {
    case improved, regressed, unchanged
  }

  public struct Metric: Equatable, Sendable {
    public var name: String
    /// The median across the "before" runs.
    public var before: Double
    /// The median across the "after" runs.
    public var after: Double
    /// The range (largest minus smallest) across the "before" runs.
    public var noise: Double
    public var verdict: Verdict
    /// The figure of each "before" run, in the order the runs were given.
    public var beforeRuns: [Double]
    /// The figure of each "after" run, in the order the runs were given.
    public var afterRuns: [Double]

    public var delta: Double { after - before }
  }

  public var metrics: [Metric]

  /// Compares the two sets. Metrics that are missing on either side are left out.
  public init(before: [Summary], after: [Summary]) {
    let beforeRuns = before.map(\.metrics)
    let afterRuns = after.map(\.metrics)
    let names = Set(beforeRuns.flatMap(\.keys)).intersection(afterRuns.flatMap(\.keys))

    metrics = names.sorted().map { name in
      let beforeValues = beforeRuns.compactMap { $0[name] }
      let afterValues = afterRuns.compactMap { $0[name] }
      let beforeMedian = Statistics.median(beforeValues)
      let afterMedian = Statistics.median(afterValues)
      let noise = (beforeValues.max() ?? 0) - (beforeValues.min() ?? 0)
      let delta = afterMedian - beforeMedian
      // Rounding alone moves a figure by a fraction of a percent, so a change also has to be
      // at least 1% of the "before" value.
      let threshold = max(noise, abs(beforeMedian) * 0.01)
      let verdict: Verdict =
        abs(delta) <= threshold ? .unchanged : (delta < 0 ? .improved : .regressed)
      return Metric(
        name: name, before: beforeMedian, after: afterMedian, noise: noise, verdict: verdict,
        beforeRuns: beforeValues, afterRuns: afterValues)
    }
  }
}

/// Upper limits for metrics, read from a JSON object such as
/// `{"hitchTimeRatio": 5, "image.load[hit].p95": 16}`.
public struct Goals: Equatable, Sendable {
  public struct Violation: Equatable, Sendable {
    public var name: String
    public var limit: Double
    public var actual: Double
  }

  public var limits: [String: Double]

  public init(limits: [String: Double]) {
    self.limits = limits
  }

  public static func load(from url: URL) throws -> Goals {
    Goals(limits: try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url)))
  }

  /// Returns the goals that the given figures exceed.
  public func violations(in metrics: [String: Double]) -> [Violation] {
    limits.keys.sorted().compactMap { name in
      guard let limit = limits[name], let actual = metrics[name], actual > limit else { return nil }
      return Violation(name: name, limit: limit, actual: actual)
    }
  }

  /// Returns the goals that have no figure to check.
  ///
  /// A goal goes unchecked when its name does not match what the app records, because of a
  /// typo or a renamed series, and when the session never reached that part of the app. Either
  /// way the goal was not met; it was not looked at.
  public func unchecked(in metrics: [String: Double]) -> [String] {
    limits.keys.filter { metrics[$0] == nil }.sorted()
  }

  /// The median of each metric across several runs.
  public static func medians(of summaries: [Summary]) -> [String: Double] {
    let runs = summaries.map(\.metrics)
    var medians: [String: Double] = [:]
    for name in Set(runs.flatMap(\.keys)) {
      medians[name] = Statistics.median(runs.compactMap { $0[name] })
    }
    return medians
  }
}
