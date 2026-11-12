import Foundation

/// What one launch of the app recorded. This is the file format shared by the recorder and
/// the `hitch` command line tool.
public struct Recording: Codable, Equatable, Sendable {
  /// The current file format version.
  public static let currentVersion = 1

  public struct Device: Codable, Equatable, Sendable {
    /// The hardware identifier, such as `iPhone17,1`.
    public var model: String
    public var systemName: String
    public var systemVersion: String

    public init(model: String, systemName: String, systemVersion: String) {
      self.model = model
      self.systemName = systemName
      self.systemVersion = systemVersion
    }
  }

  public struct App: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var version: String
    public var build: String

    public init(bundleIdentifier: String, version: String, build: String) {
      self.bundleIdentifier = bundleIdentifier
      self.version = version
      self.build = build
    }
  }

  /// Display refresh callbacks, in the order they arrived.
  public struct Frames: Codable, Equatable, Sendable {
    /// The time since the previous callback, in milliseconds.
    public var intervals: [Double]
    /// The time the display expected between the two callbacks, in milliseconds.
    public var expected: [Double]

    public init(intervals: [Double] = [], expected: [Double] = []) {
      self.intervals = intervals
      self.expected = expected
    }
  }

  public var version: Int
  public var startedAt: Date
  public var endedAt: Date
  public var device: Device
  public var app: App
  /// Free-form values supplied by the app, such as a git commit.
  public var metadata: [String: String]
  public var frames: Frames
  /// Named durations in milliseconds.
  public var samples: [String: [Double]]

  public init(
    version: Int = Recording.currentVersion,
    startedAt: Date,
    endedAt: Date,
    device: Device,
    app: App,
    metadata: [String: String] = [:],
    frames: Frames = Frames(),
    samples: [String: [Double]] = [:]
  ) {
    self.version = version
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.device = device
    self.app = app
    self.metadata = metadata
    self.frames = frames
    self.samples = samples
  }

  /// Reads a recording from disk.
  public static func load(from url: URL) throws -> Recording {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Recording.self, from: Data(contentsOf: url))
  }

  /// Encodes the recording as JSON.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }
}
