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

  /// A begun interval. Pass it to ``endInterval(_:_:tag:_:)``.
  public struct IntervalState: @unchecked Sendable {
    // `OSSignpostIntervalState` is immutable once created.
    let signpostState: OSSignpostIntervalState
    /// `nil` when no recording was running at the beginning.
    let start: UInt64?
  }

  /// Begins an interval.
  ///
  /// - Parameters:
  ///   - name: The name of the signpost, and of the series the interval's length is stored in.
  ///   - id: Tells apart intervals of the same name that overlap.
  ///   - message: Text to show with the signpost in Instruments. It is logged as public, and
  ///     only built when signposts are being collected.
  public func beginInterval(
    _ name: StaticString, id: OSSignpostID = .exclusive, _ message: @autoclosure () -> String = ""
  ) -> IntervalState {
    let state: OSSignpostIntervalState
    if signposter.isEnabled {
      let text = message()
      state =
        text.isEmpty
        ? signposter.beginInterval(name, id: id)
        : signposter.beginInterval(name, id: id, "\(text, privacy: .public)")
    } else {
      state = signposter.beginInterval(name, id: id)
    }
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
  ///   - state: What ``beginInterval(_:id:_:)`` returned.
  ///   - tag: How the interval ended, when that changes what its length means. Each tag gets
  ///     its own figures, and the tag is shown with the signpost in Instruments.
  ///   - message: More text to show with the signpost in Instruments, such as a count. It is
  ///     logged as public, and only built when signposts are being collected.
  public func endInterval(
    _ name: StaticString, _ state: IntervalState, tag: String? = nil,
    _ message: @autoclosure () -> String = ""
  ) {
    // The length is taken first, so that building the message is not part of it.
    let end = DispatchTime.now().uptimeNanoseconds
    if signposter.isEnabled {
      let text = [tag ?? "", message()].filter { !$0.isEmpty }.joined(separator: " ")
      if text.isEmpty {
        signposter.endInterval(name, state.signpostState)
      } else {
        signposter.endInterval(name, state.signpostState, "\(text, privacy: .public)")
      }
    } else {
      signposter.endInterval(name, state.signpostState)
    }
    guard let start = state.start else { return }
    Recorder.shared.endInterval("\(name)", tag: tag, Double(end &- start) / 1_000_000)
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
