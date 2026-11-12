import ArgumentParser
import Foundation
import Hitch

@main
struct HitchCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hitch",
    abstract: "Record frame pacing on a device by hand, then compare before and after.",
    version: "0.1.0",
    subcommands: [Record.self, Report.self, Compare.self]
  )
}

struct Report: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Print the figures of one or more recordings.")

  @Argument(help: "Recording files.", completion: .file(extensions: ["json"]))
  var recordings: [String]

  func run() throws {
    for path in recordings {
      let recording = try Recording.load(from: URL(fileURLWithPath: path))
      print(Format.report(recording, title: path))
    }
  }
}

struct Compare: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Compare the median of several runs before and after a change.",
    discussion: """
      Record each side several times; three runs each is a good start. A change counts only \
      when it is larger than the spread among the "before" runs, so record the "before" side \
      more often when the result is close.
      """
  )

  @Option(name: .long, parsing: .upToNextOption, help: "Recordings made before the change.")
  var before: [String]

  @Option(name: .long, parsing: .upToNextOption, help: "Recordings made after the change.")
  var after: [String]

  @Option(name: .long, help: "A JSON file of upper limits, such as {\"hitchTimeRatio\": 5}.")
  var goals: String?

  @Flag(name: .long, help: "Exit with a failure when a metric regressed.")
  var failOnRegression = false

  func validate() throws {
    guard !before.isEmpty, !after.isEmpty else {
      throw ValidationError("Pass at least one recording to both --before and --after.")
    }
  }

  func run() throws {
    let beforeSummaries = try before.map { Summary(try Recording.load(from: URL(fileURLWithPath: $0))) }
    let afterSummaries = try after.map { Summary(try Recording.load(from: URL(fileURLWithPath: $0))) }
    let comparison = Comparison(before: beforeSummaries, after: afterSummaries)
    print(Format.comparison(comparison, beforeRuns: before.count, afterRuns: after.count))

    var failed = false
    if let goals {
      let violations = try Goals.load(from: URL(fileURLWithPath: goals))
        .violations(in: Goals.medians(of: afterSummaries))
      for violation in violations {
        print("goal missed: \(violation.name) is \(Format.number(violation.actual)), limit \(Format.number(violation.limit))")
      }
      failed = !violations.isEmpty
    }
    if failOnRegression, comparison.metrics.contains(where: { $0.verdict == .regressed }) {
      failed = true
    }
    if failed { throw ExitCode.failure }
  }
}

enum Format {
  static func number(_ value: Double) -> String {
    String(format: value >= 100 ? "%.0f" : "%.1f", value)
  }

  static func report(_ recording: Recording, title: String) -> String {
    let summary = Summary(recording)
    var lines = [
      title,
      "  \(recording.device.model), \(recording.device.systemName) \(recording.device.systemVersion)"
        + ", \(recording.app.bundleIdentifier) \(recording.app.version) (\(recording.app.build))",
    ]
    for (key, value) in recording.metadata.sorted(by: { $0.key < $1.key }) {
      lines.append("  \(key): \(value)")
    }
    if let frames = summary.frames {
      lines.append(
        "  hitch time ratio  \(number(frames.hitchTimeRatio)) ms/s (\(frames.rating.rawValue))"
          + " over \(number(frames.duration)) s, \(frames.frameCount) frames"
      )
      lines.append(
        "  hitches           \(frames.hitchCount), frames over 100 ms: \(frames.longFrameCount)"
      )
      lines.append(
        "  frame interval    p50 \(number(frames.p50)) ms, p95 \(number(frames.p95)) ms, max \(number(frames.max)) ms"
      )
    } else {
      lines.append("  no frames recorded")
    }
    let rows = summary.samples.sorted { $0.key < $1.key }.map { name, statistics in
      [name, "\(statistics.count)", number(statistics.p50), number(statistics.p95), number(statistics.max)]
    }
    if !rows.isEmpty {
      lines.append("")
      lines += table(header: ["sample", "count", "p50", "p95", "max"], rows: rows).map { "  \($0)" }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  static func comparison(_ comparison: Comparison, beforeRuns: Int, afterRuns: Int) -> String {
    let rows = comparison.metrics.map { metric in
      [
        metric.name,
        number(metric.before),
        number(metric.after),
        (metric.delta > 0 ? "+" : "") + number(metric.delta),
        number(metric.noise),
        metric.verdict.rawValue,
      ]
    }
    var lines = ["median of \(beforeRuns) run(s) before, \(afterRuns) run(s) after"]
    lines += table(header: ["metric", "before", "after", "change", "noise", "verdict"], rows: rows)
    if beforeRuns < 2 {
      lines.append("note: with one run before the change, noise is unknown and every difference counts.")
    }
    return lines.joined(separator: "\n")
  }

  static func table(header: [String], rows: [[String]]) -> [String] {
    let all = [header] + rows
    let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
    return all.map { row in
      row.enumerated().map { column, cell in
        // The first column holds names and reads best left-aligned; the rest are numbers.
        let padding = String(repeating: " ", count: widths[column] - cell.count)
        return column == 0 ? cell + padding : padding + cell
      }
      .joined(separator: "  ")
      .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }
  }
}
