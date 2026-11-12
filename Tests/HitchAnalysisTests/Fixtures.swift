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

/// A recording with sensible defaults, for tests that only care about a few fields.
func makeRecording(
  intervals: [Double] = [],
  expected: Double = 10,
  series: [Recording.Series] = [],
  model: String = "iPhone17,1",
  systemVersion: String = "18.2.0",
  maximumFramesPerSecond: Int? = 120,
  configuration: Recording.App.Configuration = .release,
  thermalState: Recording.Conditions.ThermalState = .nominal,
  isLowPowerModeEnabled: Bool = false,
  metadata: [String: String] = [:],
  unfinishedIntervals: [String: Int] = [:]
) -> Recording {
  var frames = Recording.Frames()
  for interval in intervals {
    frames.append(interval: interval, expected: expected)
  }
  let conditions = Recording.Conditions(
    thermalState: thermalState, isLowPowerModeEnabled: isLowPowerModeEnabled,
    batteryState: .unplugged)
  return Recording(
    startedAt: Date(timeIntervalSince1970: 0),
    endedAt: Date(timeIntervalSince1970: 60),
    secondsSinceLaunch: 0.5,
    device: .init(
      model: model, systemName: "iOS", systemVersion: systemVersion,
      maximumFramesPerSecond: maximumFramesPerSecond),
    app: .init(
      bundleIdentifier: "com.example.app", version: "1.0", build: "1", configuration: configuration),
    conditionsAtStart: conditions,
    conditionsAtEnd: conditions,
    metadata: metadata,
    frames: frames,
    series: series,
    unfinishedIntervals: unfinishedIntervals
  )
}
