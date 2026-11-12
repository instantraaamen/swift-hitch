import Foundation
import os

/// Collects samples and writes them to disk. All access goes through one lock, so samples can
/// be added from any thread.
final class Recorder: Sendable {
  struct State {
    var isRecording = false
    var startedAt = Date()
    var metadata: [String: String] = [:]
    var fileURL: URL?
    var frames = Recording.Frames()
    var samples: [String: [Double]] = [:]
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
  func start(directory: URL, metadata: [String: String], now: Date = Date()) -> Bool {
    state.withLock { state in
      guard !state.isRecording else { return false }
      state = State()
      state.isRecording = true
      state.startedAt = now
      state.metadata = metadata
      state.fileURL = directory.appendingPathComponent(Self.fileName(for: now))
      return true
    }
  }

  func stop() {
    flush()
    state.withLock { $0.isRecording = false }
  }

  func addSample(_ name: String, _ milliseconds: Double) {
    state.withLock { state in
      guard state.isRecording else { return }
      state.samples[name, default: []].append(milliseconds)
      state.isDirty = true
    }
  }

  func addFrame(interval: Double, expected: Double) {
    state.withLock { state in
      guard state.isRecording else { return }
      state.frames.intervals.append(interval)
      state.frames.expected.append(expected)
      state.isDirty = true
    }
  }

  /// Writes the recording if anything was added since the last write. Safe to call often.
  func flush(now: Date = Date()) {
    let pending: (Recording, URL)? = state.withLock { state in
      guard state.isRecording, state.isDirty, let url = state.fileURL else { return nil }
      state.isDirty = false
      let recording = Recording(
        startedAt: state.startedAt,
        endedAt: now,
        device: Environment.device,
        app: Environment.app,
        metadata: state.metadata,
        frames: state.frames,
        samples: state.samples
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

  static func fileName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "\(formatter.string(from: date)).json"
  }
}

enum Environment {
  static var device: Recording.Device {
    var systemInfo = utsname()
    uname(&systemInfo)
    let model = withUnsafeBytes(of: &systemInfo.machine) { buffer in
      String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #if os(iOS)
      let systemName = "iOS"
    #elseif os(tvOS)
      let systemName = "tvOS"
    #else
      let systemName = "macOS"
    #endif
    // The simulator reports the host's hardware; the simulated model is in the environment.
    let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
    return Recording.Device(
      model: simulated.map { "\($0) (Simulator)" } ?? model,
      systemName: systemName,
      systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    )
  }

  static var app: Recording.App {
    let info = Bundle.main.infoDictionary ?? [:]
    return Recording.App(
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
      version: info["CFBundleShortVersionString"] as? String ?? "",
      build: info["CFBundleVersion"] as? String ?? ""
    )
  }
}
