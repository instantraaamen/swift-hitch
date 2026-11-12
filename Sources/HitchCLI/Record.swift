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
import HitchRecording

struct Record: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "Launch the app with recording on, wait while you use it, then collect the recording.",
    discussion: """
      The app must call Hitch.startIfRequested() at launch. Use the app the same way for every \
      run you intend to compare: same screens, same gestures, about the same length. Keep the \
      device in the same state as well: unplugged or charging, cool, Low Power Mode off.
      """
  )

  @Option(name: .long, help: "The UDID of a connected device.")
  var device: String?

  @Option(name: .long, help: "The UDID of a simulator, or \"booted\".")
  var simulator: String?

  @Option(name: .long, help: "The bundle identifier of the app.")
  var bundleID: String

  @Option(name: .long, help: "The directory to save recordings in.", completion: .directory)
  var output = "hitch-recordings"

  @Option(name: .long, help: "A prefix for the saved file, such as \"before\".")
  var label: String?

  @Option(
    name: .long, parsing: .singleValue,
    help: "A value to store with the recording, as key=value. May be repeated.")
  var metadata: [String] = []

  @Flag(
    name: .long, help: "Do not store the git commit of the current directory with the recording.")
  var noCommit = false

  @Argument(parsing: .postTerminator, help: "Extra launch arguments for the app, after --.")
  var appArguments: [String] = []

  // The same strings as `Hitch.launchArgument` and `Hitch.metadataArgument`. The tool does not
  // link the recorder, which only builds where the app runs.
  static let recordArgument = "--hitch-record"
  static let metadataArgument = "--hitch-metadata"

  func validate() throws {
    guard (device != nil) != (simulator != nil) else {
      throw ValidationError("Pass exactly one of --device or --simulator.")
    }
    for pair in metadata where !pair.contains("=") || pair.hasPrefix("=") {
      throw ValidationError("--metadata takes key=value, got \"\(pair)\".")
    }
  }

  func run() throws {
    // The run identifier tells this launch's recording apart from older ones on the device,
    // without relying on the device's clock agreeing with this Mac's.
    let run = UUID().uuidString.lowercased()
    var pairs = metadata + ["run=\(run)"]
    if let label { pairs.append("label=\(label)") }
    if !noCommit, let commit = Git.describeHead() { pairs.append("commit=\(commit)") }
    let launchArguments =
      [Self.recordArgument] + pairs.flatMap { [Self.metadataArgument, $0] } + appArguments

    if let device {
      // The first command after a while without contact often fails while the connection to
      // the device is still being set up.
      try Shell.retrying(attempts: 3, pause: 5) {
        try Shell.run(
          "/usr/bin/xcrun",
          [
            "devicectl", "device", "process", "launch", "--device", device, "--terminate-existing",
            bundleID,
          ]
            + launchArguments
        )
      }
    } else if let simulator {
      try Shell.run(
        "/usr/bin/xcrun",
        ["simctl", "launch", "--terminate-running-process", simulator, bundleID] + launchArguments
      )
    }

    print("Recording. Use the app, then press Return here.")
    _ = readLine()
    // The app writes every two seconds. Wait for the last write before collecting.
    Thread.sleep(forTimeInterval: 2.5)

    let workspace = FileManager.default.temporaryDirectory
      .appendingPathComponent("hitch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    let recordings: URL
    if let device {
      recordings = workspace.appendingPathComponent("hitch")
      try Shell.retrying(attempts: 3, pause: 5) {
        try? FileManager.default.removeItem(at: recordings)
        try Shell.run(
          "/usr/bin/xcrun",
          [
            "devicectl", "device", "copy", "from", "--device", device,
            "--domain-type", "appDataContainer", "--domain-identifier", bundleID,
            "--source", "Documents/hitch", "--destination", recordings.path,
          ]
        )
      }
    } else {
      let container = try Shell.run(
        "/usr/bin/xcrun", ["simctl", "get_app_container", simulator ?? "booted", bundleID, "data"]
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      recordings = URL(fileURLWithPath: container).appendingPathComponent("Documents/hitch")
    }

    guard let (file, recording) = Self.recording(ofRun: run, in: recordings) else {
      throw ValidationError(
        """
        The app wrote no recording for this launch. Check that it calls Hitch.startIfRequested() \
        at launch, and that the build you launched includes that call (it is usually behind \
        #if DEBUG).
        """)
    }

    let outputDirectory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let name = [label, file.lastPathComponent].compactMap { $0 }.joined(separator: "-")
    let destination = outputDirectory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: file, to: destination)

    print(Format.report(recording, title: destination.path))
  }

  /// Finds the recording whose metadata carries the given run identifier.
  static func recording(ofRun run: String, in directory: URL) -> (URL, Recording)? {
    let files =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    // Newest first: file names start with a UTC timestamp.
    for file in files.filter({ $0.pathExtension == "json" }).sorted(by: {
      $0.lastPathComponent > $1.lastPathComponent
    }) {
      guard let recording = try? Recording.load(from: file), recording.metadata["run"] == run else {
        continue
      }
      return (file, recording)
    }
    return nil
  }
}

enum Git {
  /// The short commit of the current directory, with `-dirty` when there are uncommitted
  /// changes. `nil` outside a repository.
  static func describeHead() -> String? {
    guard
      let commit = try? Shell.run("/usr/bin/git", ["rev-parse", "--short", "HEAD"])
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !commit.isEmpty
    else { return nil }
    let status = (try? Shell.run("/usr/bin/git", ["status", "--porcelain"])) ?? ""
    return status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? commit : "\(commit)-dirty"
  }
}

struct ShellError: Error, CustomStringConvertible {
  var command: String
  var status: Int32
  var output: String

  var description: String { "`\(command)` exited with status \(status).\n\(output)" }
}

enum Shell {
  @discardableResult
  static func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw ShellError(
        command: ([executable] + arguments).joined(separator: " "),
        status: process.terminationStatus,
        output: output
      )
    }
    return output
  }

  /// Runs `body` again after a pause when it throws, up to `attempts` times in all.
  static func retrying(attempts: Int, pause: TimeInterval, _ body: () throws -> Void) throws {
    for attempt in 1...attempts {
      do {
        return try body()
      } catch  where attempt < attempts {
        print("That did not work (\(error)). Trying again in \(Int(pause)) s.")
        Thread.sleep(forTimeInterval: pause)
      }
    }
  }
}
