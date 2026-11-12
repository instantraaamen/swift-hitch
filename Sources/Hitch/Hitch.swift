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

/// Records frame pacing and named durations inside the app, without a test runner attached.
///
/// Driving an app from a UI test turns accessibility on and reads the view hierarchy after
/// every action, which keeps the main thread busy and inflates the very figures you are trying
/// to measure. `Hitch` lets the app measure itself while a person uses it.
///
/// Start the recorder as early as possible, behind a launch argument:
///
/// ```swift
/// @main struct MyApp: App {
///   init() {
///     #if DEBUG
///       Hitch.startIfRequested()
///     #endif
///   }
/// }
/// ```
///
/// Then launch with `--hitch-record`, or let `hitch record` do it. Every call is a cheap
/// no-op until a recording has started.
public enum Hitch {
  /// The launch argument ``startIfRequested(metadata:arguments:)`` looks for.
  public static let launchArgument = "--hitch-record"

  /// The launch argument that adds a value to the recording's metadata. It is followed by
  /// `key=value`, and may be passed several times. `hitch record` uses it to store the label
  /// and the git commit.
  public static let metadataArgument = "--hitch-metadata"

  /// The directory recordings are written to: `Documents/hitch`.
  public static var defaultDirectory: URL {
    let documents =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return documents.appendingPathComponent("hitch")
  }

  /// Whether a recording is running.
  public static var isRecording: Bool { Recorder.shared.isRecording }

  /// Starts recording when the process was launched with ``launchArgument``.
  ///
  /// - Parameters:
  ///   - metadata: Values to store with the recording, such as how much data the app holds.
  ///     Values passed with ``metadataArgument`` are added, and win over these.
  ///   - arguments: The launch arguments to inspect.
  /// - Returns: Whether a recording was started.
  @MainActor
  @discardableResult
  public static func startIfRequested(
    metadata: [String: String] = [:],
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    guard arguments.contains(launchArgument) else { return false }
    return start(
      metadata: metadata.merging(self.metadata(in: arguments)) { _, argument in argument })
  }

  /// Starts recording frame intervals and durations.
  ///
  /// The recording is written to `directory` every few seconds and when the app moves to the
  /// background, so nothing has to be called at the end.
  ///
  /// - Returns: `false` when a recording was already running.
  @MainActor
  @discardableResult
  public static func start(metadata: [String: String] = [:], directory: URL? = nil) -> Bool {
    let started = Recorder.shared.start(
      directory: directory ?? defaultDirectory,
      metadata: metadata,
      environment: Environment.current()
    )
    guard started else { return false }
    Recorder.shared.scheduleFlushes(every: 2)
    #if canImport(UIKit) && !os(watchOS)
      FrameMonitor.shared.start()
    #endif
    return true
  }

  /// Stops recording and writes what was collected.
  @MainActor
  public static func stop() {
    #if canImport(UIKit) && !os(watchOS)
      FrameMonitor.shared.stop()
    #endif
    Recorder.shared.stop()
  }

  /// Adds one duration to a series.
  ///
  /// - Parameters:
  ///   - name: The series, such as `image.load`.
  ///   - tag: Tells apart durations that share a name but are not comparable, such as `hit`
  ///     and `miss`. Each tag gets its own figures.
  ///   - milliseconds: The duration.
  public static func sample(_ name: String, tag: String? = nil, milliseconds: Double) {
    Recorder.shared.addSample(name, tag: tag, milliseconds)
  }

  /// Runs `body` and adds how long it took to a series.
  public static func measure<Result>(
    _ name: String, tag: String? = nil, _ body: () throws -> Result
  ) rethrows -> Result {
    guard isRecording else { return try body() }
    let start = DispatchTime.now().uptimeNanoseconds
    defer {
      sample(
        name, tag: tag,
        milliseconds: Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
    }
    return try body()
  }

  /// Marks the moment the app starts handling a touch.
  ///
  /// Call this at the top of a tap handler. It records how long the touch waited before the
  /// handler ran and how the following frames went:
  ///
  /// - `<name>.touchUpToHandler`: from the finger lifting to this call.
  /// - `<name>.touchDownToHandler`: from the finger landing to this call.
  /// - `<name>.firstFrame`: from the finger lifting to the next frame.
  /// - `<name>.longestFrameAfter`: the longest frame in the ``interactionWindow`` after that.
  ///
  /// The window is a length of time, not a number of frames, so that the figure means the
  /// same on a 60 Hz and a 120 Hz display.
  ///
  /// - Parameters:
  ///   - name: The interaction, such as `open.detail`.
  ///   - tag: Tells apart interactions that share a name but are not comparable, such as where
  ///     in a long list the tap happened.
  @MainActor
  public static func markInteraction(_ name: String, tag: String? = nil) {
    #if canImport(UIKit) && !os(watchOS)
      guard isRecording else { return }
      FrameMonitor.shared.markInteraction(name, tag: tag)
    #endif
  }

  /// How long after an interaction's first frame the frames are inspected, in milliseconds.
  public static let interactionWindow = 250.0

  static func metadata(in arguments: [String]) -> [String: String] {
    var metadata: [String: String] = [:]
    for (index, argument) in arguments.enumerated()
    where argument == metadataArgument && index + 1 < arguments.count {
      let pair = arguments[index + 1]
      guard let separator = pair.firstIndex(of: "="), separator != pair.startIndex else { continue }
      metadata[String(pair[..<separator])] = String(pair[pair.index(after: separator)...])
    }
    return metadata
  }
}
