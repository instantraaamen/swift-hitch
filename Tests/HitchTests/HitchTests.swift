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

@testable import Hitch

private let environment = Environment(
  device: .init(
    model: "iPhone17,1", systemName: "iOS", systemVersion: "18.2.0", maximumFramesPerSecond: 120),
  app: .init(
    bundleIdentifier: "com.example.app", version: "1.0", build: "1", configuration: .debug),
  secondsSinceLaunch: 0.4,
  conditions: { .init(thermalState: .fair, isLowPowerModeEnabled: false, batteryState: .charging) }
)

private func temporaryDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("hitch-tests-\(UUID().uuidString)")
}

private func onlyRecording(in directory: URL) throws -> Recording {
  let files = try FileManager.default.contentsOfDirectory(
    at: directory, includingPropertiesForKeys: nil)
  #expect(files.count == 1)
  return try Recording.load(from: try #require(files.first))
}

@Suite struct RecorderTests {
  @Test func ignoresEverythingUntilStarted() {
    let recorder = Recorder()
    recorder.addSample("ignored", tag: nil, 1)
    recorder.beginInterval("ignored")
    recorder.addFrame(interval: 8, expected: 8)
    #expect(!recorder.isRecording)
  }

  @Test func writesWhatWasCollected() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(
      recorder.start(
        directory: directory, metadata: ["commit": "abc123"], environment: environment, now: start))
    #expect(!recorder.start(directory: directory, metadata: [:], environment: environment))
    recorder.addSample("image.load", tag: "hit", 4)
    recorder.addSample("image.load", tag: "miss", 60)
    recorder.addSample("image.load", tag: "hit", 6)
    recorder.addFrame(interval: 8.3333333, expected: 8.3333333)
    recorder.addFrame(interval: 16.7, expected: 8.3333333)
    recorder.flush(now: start.addingTimeInterval(30))

    let recording = try Recording.load(
      from: directory.appendingPathComponent("20231114-221320-000.json"))
    #expect(recording.version == Recording.currentVersion)
    #expect(recording.metadata == ["commit": "abc123"])
    #expect(
      recording.series == [
        .init(name: "image.load", tag: "hit", values: [4, 6]),
        .init(name: "image.load", tag: "miss", values: [60]),
      ])
    #expect(recording.frames.intervals == [8.333, 16.7])
    #expect(recording.frames.expected == [.init(count: 2, interval: 8.333)])
    #expect(recording.endedAt == start.addingTimeInterval(30))
    #expect(recording.device.maximumFramesPerSecond == 120)
    #expect(recording.app.configuration == .debug)
    #expect(recording.conditionsAtStart.thermalState == .fair)
    #expect(recording.conditionsAtEnd.batteryState == .charging)
    #expect(recording.secondsSinceLaunch == 0.4)
  }

  /// A launch that records nothing still leaves a file, so "the app never started the
  /// recorder" and "the session produced no data" are told apart.
  @Test func anEmptyRecordingIsStillWritten() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    recorder.start(directory: directory, metadata: ["run": "r1"], environment: environment)
    recorder.flush()

    let recording = try onlyRecording(in: directory)
    #expect(recording.metadata == ["run": "r1"])
    #expect(recording.series.isEmpty)
  }

  @Test func stopFlushesAndEndsTheRecording() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    recorder.start(directory: directory, metadata: [:], environment: environment)
    recorder.addSample("a", tag: nil, 1)
    recorder.stop()
    recorder.addSample("a", tag: nil, 2)

    #expect(try onlyRecording(in: directory).series == [.init(name: "a", values: [1])])
  }

  /// An interval that only closes on one of its outcomes used to stay open on the others, and
  /// its figures quietly covered a subset.
  @Test func countsIntervalsThatNeverEnd() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    recorder.start(directory: directory, metadata: [:], environment: environment)
    for _ in 0..<5 { recorder.beginInterval("image.final") }
    recorder.endInterval("image.final", tag: "full", 120)
    recorder.endInterval("image.final", tag: "full", 140)
    recorder.beginInterval("image.load")
    recorder.endInterval("image.load", tag: nil, 3)
    recorder.flush()

    let recording = try onlyRecording(in: directory)
    #expect(recording.unfinishedIntervals == ["image.final": 3])
    #expect(recording.series.first { $0.name == "image.final" }?.values == [120, 140])
  }

  /// Two recordings must never share a file, or the later one replaces the earlier.
  @Test func everyStartGetsItsOwnFile() {
    let first = Recorder.fileName(for: Date(timeIntervalSince1970: 1_700_000_000.100))
    let second = Recorder.fileName(for: Date(timeIntervalSince1970: 1_700_000_000.900))
    #expect(first != second)
    #expect(first < second)
  }
}

@Suite struct LaunchArgumentTests {
  @Test func readsMetadataFromLaunchArguments() {
    let arguments = [
      "App", "--hitch-record", "--hitch-metadata", "label=before", "--other", "--hitch-metadata",
      "commit=abc123-dirty", "--hitch-metadata", "note=a=b", "--hitch-metadata", "=broken",
      "--hitch-metadata",
    ]
    #expect(
      Hitch.metadata(in: arguments) == ["label": "before", "commit": "abc123-dirty", "note": "a=b"])
    #expect(Hitch.metadata(in: ["App"]).isEmpty)
  }

  @Test @MainActor func doesNotStartWithoutTheArgument() {
    #expect(!Hitch.startIfRequested(arguments: ["App", "--something-else"]))
    #expect(!Hitch.isRecording)
  }
}
