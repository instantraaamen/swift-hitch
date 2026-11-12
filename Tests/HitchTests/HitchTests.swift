import Foundation
import Testing

@testable import Hitch

private func recording(intervals: [Double] = [], expected: Double = 10, samples: [String: [Double]] = [:]) -> Recording {
  Recording(
    startedAt: Date(timeIntervalSince1970: 0),
    endedAt: Date(timeIntervalSince1970: 60),
    device: .init(model: "iPhone17,1", systemName: "iOS", systemVersion: "18.2.0"),
    app: .init(bundleIdentifier: "com.example.app", version: "1.0", build: "1"),
    frames: .init(intervals: intervals, expected: intervals.map { _ in expected }),
    samples: samples
  )
}

@Suite struct StatisticsTests {
  @Test func percentileUsesNearestRank() {
    let values = (1...100).map(Double.init)
    #expect(Statistics.percentile(values, 0.5) == 50)
    #expect(Statistics.percentile(values, 0.95) == 95)
    #expect(Statistics.percentile([7], 0.95) == 7)
    #expect(Statistics.percentile([], 0.5) == 0)
  }

  @Test func medianAveragesTheMiddlePair() {
    #expect(Statistics.median([3, 1, 2]) == 2)
    #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
  }

  @Test func smoothFramesHaveNoHitches() throws {
    let frames = try #require(FrameStatistics(recording(intervals: Array(repeating: 10.2, count: 100)).frames))
    #expect(frames.hitchCount == 0)
    #expect(frames.hitchTimeRatio == 0)
    #expect(frames.rating == .good)
  }

  @Test func lateFramesAddUpToHitchTime() throws {
    // 98 frames on time, one dropped frame (10 ms late) and one long stall (190 ms late).
    let intervals = Array(repeating: 10.0, count: 98) + [20, 200]
    let frames = try #require(FrameStatistics(recording(intervals: intervals).frames))
    #expect(frames.hitchCount == 2)
    #expect(frames.hitchTime == 200)
    #expect(frames.longFrameCount == 1)
    #expect(frames.max == 200)
    // 200 ms late over 1.2 s of recording.
    #expect(abs(frames.hitchTimeRatio - 200 / 1.2) < 0.001)
    #expect(frames.rating == .critical)
  }

  @Test func expectedIntervalFollowsTheDisplay() throws {
    // A display that drops from 120 Hz to 60 Hz is not hitching.
    let frames = Recording.Frames(intervals: [8.3, 8.3, 16.7, 16.7], expected: [8.3, 8.3, 16.7, 16.7])
    #expect(try #require(FrameStatistics(frames)).hitchCount == 0)
  }

  @Test func emptyRecordingHasNoFrameStatistics() {
    #expect(FrameStatistics(Recording.Frames()) == nil)
    #expect(Summary(recording()).metrics.isEmpty)
  }

  @Test func summaryFlattensMetrics() {
    let summary = Summary(recording(intervals: [10, 10], samples: ["image.load": [1, 2, 3], "empty": []]))
    #expect(summary.metrics["image.load.p50"] == 2)
    #expect(summary.metrics["image.load.p95"] == 3)
    #expect(summary.metrics["hitchTimeRatio"] == 0)
    #expect(summary.metrics["empty.p50"] == nil)
  }
}

@Suite struct ComparisonTests {
  private func summary(stall: Double) -> Summary {
    Summary(recording(intervals: Array(repeating: 10.0, count: 99) + [stall]))
  }

  @Test func changeLargerThanNoiseCounts() throws {
    let comparison = Comparison(
      before: [summary(stall: 300), summary(stall: 310), summary(stall: 320)],
      after: [summary(stall: 100), summary(stall: 110), summary(stall: 90)]
    )
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .improved)
    #expect(ratio.after < ratio.before)
    #expect(ratio.noise > 0)
  }

  @Test func changeWithinNoiseIsUnchanged() throws {
    let comparison = Comparison(
      before: [summary(stall: 100), summary(stall: 300)],
      after: [summary(stall: 220)]
    )
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .unchanged)
  }

  @Test func regressionIsReported() throws {
    let comparison = Comparison(before: [summary(stall: 20)], after: [summary(stall: 400)])
    let ratio = try #require(comparison.metrics.first { $0.name == "hitchTimeRatio" })
    #expect(ratio.verdict == .regressed)
  }

  @Test func goalsReportOnlyWhatIsExceeded() {
    let goals = Goals(limits: ["hitchTimeRatio": 5, "frame.max": 500, "missing.p95": 1])
    let violations = goals.violations(in: Goals.medians(of: [summary(stall: 300), summary(stall: 300)]))
    #expect(violations.map(\.name) == ["hitchTimeRatio"])
  }
}

@Suite struct RecorderTests {
  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hitch-tests-\(UUID().uuidString)")
  }

  @Test func ignoresSamplesUntilStarted() {
    let recorder = Recorder()
    recorder.addSample("ignored", 1)
    #expect(!recorder.isRecording)
  }

  @Test func writesWhatWasCollected() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(recorder.start(directory: directory, metadata: ["commit": "abc123"], now: start))
    #expect(!recorder.start(directory: directory, metadata: [:]))
    recorder.addSample("image.load", 4)
    recorder.addSample("image.load", 6)
    recorder.addFrame(interval: 8.3, expected: 8.3)
    recorder.flush(now: start.addingTimeInterval(30))

    let file = directory.appendingPathComponent("20231114-221320.json")
    let recording = try Recording.load(from: file)
    #expect(recording.version == Recording.currentVersion)
    #expect(recording.metadata == ["commit": "abc123"])
    #expect(recording.samples == ["image.load": [4, 6]])
    #expect(recording.frames.intervals == [8.3])
    #expect(recording.endedAt == start.addingTimeInterval(30))
  }

  @Test func stopFlushesAndEndsTheRecording() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = Recorder()
    recorder.start(directory: directory, metadata: [:])
    recorder.addSample("a", 1)
    recorder.stop()
    recorder.addSample("a", 2)

    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(files.count == 1)
    #expect(try Recording.load(from: files[0]).samples == ["a": [1]])
  }

  @Test func recordingSurvivesARoundTrip() throws {
    let original = recording(intervals: [10, 20], samples: ["a": [1.5]])
    let url = temporaryDirectory().appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }
    try original.encoded().write(to: url)
    #expect(try Recording.load(from: url) == original)
  }
}
