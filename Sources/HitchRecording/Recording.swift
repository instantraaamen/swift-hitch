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

/// What one launch of the app recorded. This is the file format shared by the recorder and
/// the `hitch` command line tool.
public struct Recording: Codable, Equatable, Sendable {
  /// The current file format version.
  public static let currentVersion = 2

  /// The hardware and system the app ran on.
  public struct Device: Codable, Equatable, Sendable {
    /// The hardware identifier, such as `iPhone17,1`.
    public var model: String
    public var systemName: String
    public var systemVersion: String
    /// The highest refresh rate of the display, such as `120`. `nil` when it is not known.
    public var maximumFramesPerSecond: Int?

    public init(
      model: String, systemName: String, systemVersion: String, maximumFramesPerSecond: Int? = nil
    ) {
      self.model = model
      self.systemName = systemName
      self.systemVersion = systemVersion
      self.maximumFramesPerSecond = maximumFramesPerSecond
    }
  }

  /// The app that was measured.
  public struct App: Codable, Equatable, Sendable {
    /// How the recorder was compiled, which follows how the app was compiled.
    public enum Configuration: String, Codable, Sendable {
      /// Without optimization. Figures from a debug build are slower than what users see.
      case debug
      case release
    }

    public var bundleIdentifier: String
    public var version: String
    public var build: String
    public var configuration: Configuration

    public init(
      bundleIdentifier: String, version: String, build: String, configuration: Configuration
    ) {
      self.bundleIdentifier = bundleIdentifier
      self.version = version
      self.build = build
      self.configuration = configuration
    }
  }

  /// The state of the device at one moment. A hot or power-saving device runs slower, so two
  /// recordings are only comparable when these match.
  public struct Conditions: Codable, Equatable, Sendable {
    public enum ThermalState: String, Codable, Sendable {
      case nominal, fair, serious, critical
    }

    public enum BatteryState: String, Codable, Sendable {
      case unplugged, charging, full
    }

    public var thermalState: ThermalState
    public var isLowPowerModeEnabled: Bool
    /// `nil` when the device does not report it.
    public var batteryState: BatteryState?

    public init(
      thermalState: ThermalState, isLowPowerModeEnabled: Bool, batteryState: BatteryState? = nil
    ) {
      self.thermalState = thermalState
      self.isLowPowerModeEnabled = isLowPowerModeEnabled
      self.batteryState = batteryState
    }
  }

  /// Display refresh callbacks, in the order they arrived.
  public struct Frames: Codable, Equatable, Sendable {
    /// A stretch of consecutive callbacks for which the display expected the same interval.
    public struct ExpectedRun: Codable, Equatable, Sendable {
      public var count: Int
      /// The expected time between two callbacks, in milliseconds.
      public var interval: Double

      public init(count: Int, interval: Double) {
        self.count = count
        self.interval = interval
      }
    }

    /// The time since the previous callback, in milliseconds.
    public var intervals: [Double]
    /// The time the display expected between callbacks, as runs that add up to the number of
    /// ``intervals``. A display that changes its refresh rate produces several runs.
    public var expected: [ExpectedRun]

    public init(intervals: [Double] = [], expected: [ExpectedRun] = []) {
      self.intervals = intervals
      self.expected = expected
    }

    /// Adds one callback.
    public mutating func append(interval: Double, expected expectedInterval: Double) {
      intervals.append(interval)
      if let last = expected.indices.last, expected[last].interval == expectedInterval {
        expected[last].count += 1
      } else {
        expected.append(ExpectedRun(count: 1, interval: expectedInterval))
      }
    }

    /// The expected interval of every callback, one for each of ``intervals``. Callbacks past
    /// the end of the runs repeat the last known value.
    public var expectedIntervals: [Double] {
      var result: [Double] = []
      result.reserveCapacity(intervals.count)
      for run in expected {
        result.append(contentsOf: repeatElement(run.interval, count: run.count))
      }
      if result.count < intervals.count {
        result.append(
          contentsOf: repeatElement(result.last ?? 0, count: intervals.count - result.count))
      }
      return Array(result.prefix(intervals.count))
    }
  }

  /// The durations recorded under one name and tag.
  public struct Series: Codable, Equatable, Sendable {
    public var name: String
    /// Tells apart durations that share a name but are not comparable, such as a cache hit and
    /// a cache miss.
    public var tag: String?
    /// Durations in milliseconds, in the order they were recorded.
    public var values: [Double]

    public init(name: String, tag: String? = nil, values: [Double]) {
      self.name = name
      self.tag = tag
      self.values = values
    }

    /// The name used in reports and goals: `name`, or `name[tag]`.
    public var label: String {
      tag.map { "\(name)[\($0)]" } ?? name
    }
  }

  public var version: Int
  public var startedAt: Date
  public var endedAt: Date
  /// How long the process had been running when the recording started, in seconds. A recording
  /// that starts at launch competes with the app's own start-up work.
  public var secondsSinceLaunch: Double?
  public var device: Device
  public var app: App
  public var conditionsAtStart: Conditions
  public var conditionsAtEnd: Conditions
  /// Free-form values supplied by the app or by `hitch record`, such as a git commit.
  public var metadata: [String: String]
  public var frames: Frames
  public var series: [Series]
  /// Intervals that were begun and never ended, by name. A figure built from the ones that did
  /// end is missing these.
  public var unfinishedIntervals: [String: Int]

  public init(
    version: Int = Recording.currentVersion,
    startedAt: Date,
    endedAt: Date,
    secondsSinceLaunch: Double? = nil,
    device: Device,
    app: App,
    conditionsAtStart: Conditions,
    conditionsAtEnd: Conditions,
    metadata: [String: String] = [:],
    frames: Frames = Frames(),
    series: [Series] = [],
    unfinishedIntervals: [String: Int] = [:]
  ) {
    self.version = version
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.secondsSinceLaunch = secondsSinceLaunch
    self.device = device
    self.app = app
    self.conditionsAtStart = conditionsAtStart
    self.conditionsAtEnd = conditionsAtEnd
    self.metadata = metadata
    self.frames = frames
    self.series = series
    self.unfinishedIntervals = unfinishedIntervals
  }

  /// Thrown when a file was written in a format this version cannot read.
  public struct UnsupportedVersion: Error, CustomStringConvertible, Equatable {
    public var version: Int

    public init(version: Int) {
      self.version = version
    }

    public var description: String {
      "The recording uses format version \(version); this tool reads version \(Recording.currentVersion). "
        + "Record again with a matching version of the library."
    }
  }

  /// Reads a recording from disk.
  ///
  /// - Throws: ``UnsupportedVersion`` when the file was written in another format version.
  public static func load(from url: URL) throws -> Recording {
    try decode(Data(contentsOf: url))
  }

  /// Decodes a recording from JSON.
  public static func decode(_ data: Data) throws -> Recording {
    struct Header: Decodable { var version: Int }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let header = try decoder.decode(Header.self, from: data)
    guard header.version == currentVersion else {
      throw UnsupportedVersion(version: header.version)
    }
    return try decoder.decode(Recording.self, from: data)
  }

  /// Encodes the recording as JSON.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }
}
