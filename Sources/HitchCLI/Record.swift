import ArgumentParser
import Foundation
import Hitch

struct Record: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Launch the app with recording on, wait while you use it, then collect the recording.",
    discussion: """
      The app must call Hitch.startIfRequested() at launch. Use the app the same way for every \
      run you intend to compare: same screens, same gestures, about the same length.
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

  @Argument(parsing: .postTerminator, help: "Extra launch arguments for the app, after --.")
  var appArguments: [String] = []

  func validate() throws {
    guard (device != nil) != (simulator != nil) else {
      throw ValidationError("Pass exactly one of --device or --simulator.")
    }
  }

  func run() throws {
    let launchArguments = [Hitch.launchArgument] + appArguments
    if let device {
      try Shell.run(
        "/usr/bin/xcrun",
        ["devicectl", "device", "process", "launch", "--device", device, "--terminate-existing", bundleID]
          + launchArguments
      )
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
      try Shell.run(
        "/usr/bin/xcrun",
        [
          "devicectl", "device", "copy", "from", "--device", device,
          "--domain-type", "appDataContainer", "--domain-identifier", bundleID,
          "--source", "Documents/hitch", "--destination", recordings.path,
        ]
      )
    } else {
      let container = try Shell.run(
        "/usr/bin/xcrun", ["simctl", "get_app_container", simulator ?? "booted", bundleID, "data"]
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      recordings = URL(fileURLWithPath: container).appendingPathComponent("Documents/hitch")
    }

    // File names are UTC timestamps, so the last one by name is the launch that just ran.
    let files = try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard let latest = files.last else {
      throw ValidationError(
        "The app wrote no recording. Check that it calls Hitch.startIfRequested() at launch.")
    }

    let outputDirectory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let name = [label, latest.lastPathComponent].compactMap { $0 }.joined(separator: "-")
    let destination = outputDirectory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: latest, to: destination)

    print(Format.report(try Recording.load(from: destination), title: destination.path))
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
}
