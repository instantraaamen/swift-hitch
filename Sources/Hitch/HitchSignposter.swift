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
import os

/// Emits signposts and records the same intervals into the running recording.
///
/// Use it in place of `OSSignposter`. Instruments sees the signposts as usual, and when a
/// recording is running the length of every interval is stored under the signpost's name, so
/// the same figures are available on a device that Instruments cannot attach to.
///
/// ```swift
/// let signposter = HitchSignposter(subsystem: "com.example.app", category: "Images")
///
/// let state = signposter.beginInterval("image.load")
/// let image = try await load(url)
/// signposter.endInterval("image.load", state, tag: image.wasCached ? "hit" : "miss")
/// ```
///
/// An interval that is begun and never ended is counted, and reported as unfinished.
public struct HitchSignposter: Sendable {
  /// The signposter underneath, for signposts that need a message.
  public let signposter: OSSignposter

  /// Creates a signposter that logs to the given subsystem and category.
  public init(subsystem: String, category: String) {
    signposter = OSSignposter(subsystem: subsystem, category: category)
  }

  /// Wraps an existing signposter.
  public init(_ signposter: OSSignposter) {
    self.signposter = signposter
  }

  /// A begun interval. Pass it to ``endInterval(_:_:tag:)``.
  public struct IntervalState: @unchecked Sendable {
    // `OSSignpostIntervalState` is immutable once created.
    let signpostState: OSSignpostIntervalState
    /// `nil` when no recording was running at the beginning.
    let start: UInt64?
  }

  /// Begins an interval.
  public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> IntervalState {
    let state = signposter.beginInterval(name, id: id)
    guard Recorder.shared.isRecording else {
      return IntervalState(signpostState: state, start: nil)
    }
    Recorder.shared.beginInterval("\(name)")
    return IntervalState(signpostState: state, start: DispatchTime.now().uptimeNanoseconds)
  }

  /// Ends an interval and records its length.
  ///
  /// - Parameters:
  ///   - name: The name the interval was begun with.
  ///   - state: What ``beginInterval(_:id:)`` returned.
  ///   - tag: How the interval ended, when that changes what its length means. Each tag gets
  ///     its own figures.
  public func endInterval(_ name: StaticString, _ state: IntervalState, tag: String? = nil) {
    signposter.endInterval(name, state.signpostState)
    guard let start = state.start else { return }
    let milliseconds = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
    Recorder.shared.endInterval("\(name)", tag: tag, milliseconds)
  }

  /// Runs `body` inside an interval.
  public func withIntervalSignpost<Result>(
    _ name: StaticString, tag: String? = nil, around body: () throws -> Result
  ) rethrows -> Result {
    let state = beginInterval(name)
    defer { endInterval(name, state, tag: tag) }
    return try body()
  }

  /// Emits an event. Events are not recorded; they are for Instruments.
  public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {
    signposter.emitEvent(name, id: id)
  }
}
