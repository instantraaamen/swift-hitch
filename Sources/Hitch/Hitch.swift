import Foundation

/// Records frame pacing and named durations inside the app, without a test runner attached.
///
/// Driving an app from XCUITest turns accessibility on and reads the view hierarchy after
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
  ///   - metadata: Values to store with the recording, such as a git commit.
  ///   - arguments: The launch arguments to inspect.
  /// - Returns: Whether a recording was started.
  @MainActor
  @discardableResult
  public static func startIfRequested(
    metadata: [String: String] = [:],
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    guard arguments.contains(launchArgument) else { return false }
    return start(metadata: metadata)
  }

  /// Starts recording frame intervals and samples.
  ///
  /// The recording is written to `directory` every few seconds and when the app moves to the
  /// background, so nothing has to be called at the end.
  ///
  /// - Returns: `false` when a recording was already running.
  @MainActor
  @discardableResult
  public static func start(metadata: [String: String] = [:], directory: URL? = nil) -> Bool {
    guard Recorder.shared.start(directory: directory ?? defaultDirectory, metadata: metadata) else {
      return false
    }
    Recorder.shared.scheduleFlushes(every: 2)
    #if os(iOS) || os(tvOS)
      FrameMonitor.shared.start()
    #endif
    return true
  }

  /// Stops recording and writes what was collected.
  @MainActor
  public static func stop() {
    #if os(iOS) || os(tvOS)
      FrameMonitor.shared.stop()
    #endif
    Recorder.shared.stop()
  }

  /// Adds one duration to the named series.
  public static func sample(_ name: String, milliseconds: Double) {
    Recorder.shared.addSample(name, milliseconds)
  }

  /// A point in time to pass to ``sample(_:since:)``.
  public static func now() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }

  /// Adds the time elapsed since `start` to the named series.
  public static func sample(_ name: String, since start: UInt64) {
    guard isRecording else { return }
    sample(name, milliseconds: Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000)
  }

  /// Runs `body` and adds how long it took to the named series.
  public static func measure<Result>(_ name: String, _ body: () throws -> Result) rethrows -> Result {
    let start = now()
    defer { sample(name, since: start) }
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
  /// - `<name>.longestFrameAfter`: the longest of the 30 frames after that.
  @MainActor
  public static func markInteraction(_ name: String) {
    #if os(iOS) || os(tvOS)
      guard isRecording else { return }
      FrameMonitor.shared.markInteraction(name)
    #endif
  }
}
