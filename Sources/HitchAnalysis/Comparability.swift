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

/// Checks whether recordings were made under conditions that allow them to be compared.
///
/// A before/after difference means something only when the change under test is the only
/// thing that differs. A hotter device, another display refresh rate, a debug build on one
/// side or ten times as much data in the app each move the figures by more than most changes
/// do.
public enum Comparability {
  /// The metadata keys that are expected to differ between runs.
  public static let ignoredMetadataKeys: Set<String> = ["label", "commit", "run"]

  /// Describes every way in which the recordings are not comparable. Empty when they are.
  public static func issues(among recordings: [Recording]) -> [String] {
    var issues: [String] = []

    func distinct(_ values: [String]) -> [String] {
      var seen = Set<String>()
      return values.filter { seen.insert($0).inserted }
    }
    func differs(_ what: String, _ values: [String]) {
      let values = distinct(values)
      if values.count > 1 {
        issues.append("\(what) differs: \(values.joined(separator: ", ")).")
      }
    }

    differs("The device", recordings.map(\.device.model))
    differs(
      "The system version", recordings.map { "\($0.device.systemName) \($0.device.systemVersion)" })
    differs("The build configuration", recordings.map(\.app.configuration.rawValue))
    differs(
      "The display's maximum refresh rate",
      recordings.compactMap { $0.device.maximumFramesPerSecond.map { "\($0) Hz" } })
    differs(
      "The frame interval the display ran at",
      recordings.compactMap { recording in
        FrameStatistics(recording.frames).map {
          String(format: "%.1f ms", $0.typicalExpectedInterval)
        }
      })
    differs(
      "Low Power Mode",
      recordings.map {
        $0.conditionsAtStart.isLowPowerModeEnabled || $0.conditionsAtEnd.isLowPowerModeEnabled
          ? "on" : "off"
      })

    let hot = recordings.filter { recording in
      [recording.conditionsAtStart.thermalState, recording.conditionsAtEnd.thermalState]
        .contains { $0 == .serious || $0 == .critical }
    }
    if !hot.isEmpty {
      issues.append(
        "\(hot.count) of \(recordings.count) recordings were made on a hot device, which the system slows down."
      )
    }

    let keys = Set(recordings.flatMap(\.metadata.keys)).subtracting(ignoredMetadataKeys)
    for key in keys.sorted() {
      differs("The metadata value `\(key)`", recordings.map { $0.metadata[key] ?? "(none)" })
    }

    let durations = recordings.compactMap { FrameStatistics($0.frames)?.duration }
    if let shortest = durations.min(), let longest = durations.max(), shortest > 0,
      longest > shortest * 2
    {
      issues.append(
        String(
          format:
            "The recordings differ in length, from %.0f s to %.0f s. Use the app the same way for every run.",
          shortest, longest))
    }
    return issues
  }

  /// Describes what makes the figures of these recordings unrepresentative, even when they are
  /// comparable with each other.
  public static func cautions(about recordings: [Recording]) -> [String] {
    var cautions: [String] = []
    if recordings.contains(where: { $0.app.configuration == .debug }) {
      cautions.append(
        "Recorded from a debug build. It is not optimized, so durations are longer than in a release build."
      )
    }
    if recordings.contains(where: { $0.device.model.hasSuffix("(Simulator)") }) {
      cautions.append(
        "Recorded in the simulator, which runs on the Mac's hardware. Record on a device for figures that mean something."
      )
    }
    return cautions
  }
}
