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
import os

/// Collects durations and frames and writes them to disk. All access goes through one lock, so
/// values can be added from any thread.
final class Recorder: Sendable {
  struct SeriesKey: Hashable {
    var name: String
    var tag: String?
  }

  struct State {
    var isRecording = false
    var startedAt = Date()
    var metadata: [String: String] = [:]
    var environment: Environment?
    var conditionsAtStart = Recording.Conditions(
      thermalState: .nominal, isLowPowerModeEnabled: false)
    var fileURL: URL?
    var frames = Recording.Frames()
    var series: [SeriesKey: [Double]] = [:]
    /// The order series were first seen in, so that the file does not reshuffle between writes.
    var seriesOrder: [SeriesKey] = []
    var begun: [String: Int] = [:]
    var ended: [String: Int] = [:]
    var isDirty = false
  }

  static let shared = Recorder()

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let writeQueue = DispatchQueue(label: "swift-hitch.writer", qos: .utility)

  var isRecording: Bool {
    state.withLock { $0.isRecording }
  }

  /// Starts collecting. Returns `false` when a recording is already running.
  @discardableResult
  func start(
    directory: URL, metadata: [String: String], environment: Environment, now: Date = Date()
  ) -> Bool {
    let conditions = environment.conditions()
    return state.withLock { state in
      guard !state.isRecording else { return false }
      state = State()
      state.isRecording = true
      state.startedAt = now
      state.metadata = metadata
      state.environment = environment
      state.conditionsAtStart = conditions
      state.fileURL = directory.appendingPathComponent(Self.fileName(for: now))
      // Written even when nothing is recorded, so that an empty recording is told apart from
      // an app that never started the recorder.
      state.isDirty = true
      return true
    }
  }

  func stop() {
    flush()
    state.withLock { $0.isRecording = false }
  }

  func addSample(_ name: String, tag: String?, _ milliseconds: Double) {
    state.withLock { state in
      guard state.isRecording else { return }
      Self.append(milliseconds, to: SeriesKey(name: name, tag: tag), in: &state)
    }
  }

  func beginInterval(_ name: String) {
    state.withLock { state in
      guard state.isRecording else { return }
      state.begun[name, default: 0] += 1
      state.isDirty = true
    }
  }

  func endInterval(_ name: String, tag: String?, _ milliseconds: Double) {
    state.withLock { state in
      guard state.isRecording else { return }
      state.ended[name, default: 0] += 1
      Self.append(milliseconds, to: SeriesKey(name: name, tag: tag), in: &state)
    }
  }

  func addFrame(interval: Double, expected: Double) {
    state.withLock { state in
      guard state.isRecording else { return }
      state.frames.append(interval: Self.rounded(interval), expected: Self.rounded(expected))
      state.isDirty = true
    }
  }

  private static func append(_ milliseconds: Double, to key: SeriesKey, in state: inout State) {
    if state.series[key] == nil { state.seriesOrder.append(key) }
    state.series[key, default: []].append(rounded(milliseconds))
    state.isDirty = true
  }

  /// A microsecond is far below what the clock and the display resolve, and keeps the file small.
  private static func rounded(_ milliseconds: Double) -> Double {
    (milliseconds * 1000).rounded() / 1000
  }

  /// Writes the recording if anything was added since the last write. Safe to call often.
  func flush(now: Date = Date()) {
    let pending: (Recording, URL)? = state.withLock { state in
      guard state.isRecording, state.isDirty, let url = state.fileURL,
        let environment = state.environment
      else { return nil }
      state.isDirty = false
      var unfinished: [String: Int] = [:]
      for (name, begun) in state.begun {
        let open = begun - (state.ended[name] ?? 0)
        if open > 0 { unfinished[name] = open }
      }
      let recording = Recording(
        startedAt: state.startedAt,
        endedAt: now,
        secondsSinceLaunch: environment.secondsSinceLaunch,
        device: environment.device,
        app: environment.app,
        conditionsAtStart: state.conditionsAtStart,
        conditionsAtEnd: environment.conditions(),
        metadata: state.metadata,
        frames: state.frames,
        series: state.seriesOrder.map {
          Recording.Series(name: $0.name, tag: $0.tag, values: state.series[$0] ?? [])
        },
        unfinishedIntervals: unfinished
      )
      return (recording, url)
    }
    guard let (recording, url) = pending else { return }
    writeQueue.sync {
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try recording.encoded().write(to: url, options: .atomic)
      } catch {
        // A failed write must not disturb the app being measured. The next flush retries.
        state.withLock { $0.isDirty = true }
      }
    }
  }

  /// Flushes on a background queue every `interval` seconds until the recording stops.
  func scheduleFlushes(every interval: TimeInterval) {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval) { [self] in
      guard isRecording else { return }
      flush()
      scheduleFlushes(every: interval)
    }
  }

  /// One file per start, named after the moment it started, so that a recording is never
  /// overwritten by a later one.
  static func fileName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return "\(formatter.string(from: date)).json"
  }
}
