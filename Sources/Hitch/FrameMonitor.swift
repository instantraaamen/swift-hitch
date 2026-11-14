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

#if canImport(UIKit) && !os(watchOS)
  import UIKit

  /// Watches the display link on the main run loop.
  ///
  /// A late callback means the main thread was busy when the display asked for a frame. Work
  /// that is late on the render server alone does not show up here; use Instruments for that.
  @MainActor
  final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()

    private struct Interaction {
      var name: String
      var tag: String?
      /// When the first frame after the interaction arrived. `nil` until it does.
      var firstFrameAt: CFTimeInterval?
      var longest = 0.0
    }

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var pending: Interaction?
    private var framesUntilRefresh = 30

    /// A touch older than this is not the one being handled. It guards against an interaction
    /// that is marked from somewhere other than a touch handler.
    private static let touchValidity: TimeInterval = 2

    func start() {
      guard link == nil else { return }
      let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
      link.add(to: .main, forMode: .common)
      self.link = link
      followDisplay()

      let center = NotificationCenter.default
      observers = [
        // The display link pauses in the background. Without this, the first frame after
        // coming back would be recorded as a hitch that lasted the whole absence.
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) {
          [weak self] _ in
          MainActor.assumeIsolated {
            self?.lastTimestamp = 0
            self?.pending = nil
            self?.installTouchRecorder()
            DeviceState.refresh()
            self?.followDisplay()
          }
        },
        center.addObserver(
          forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) {
          [weak self] _ in
          MainActor.assumeIsolated {
            self?.lastTimestamp = 0
            self?.pending = nil
            DeviceState.refresh()
          }
          // The app may be suspended or ended from here on, so write what there is.
          Recorder.shared.flush()
        },
      ]
      installTouchRecorder()
      DeviceState.refresh()
      followDisplay()
    }

    /// Lets the display link run as fast as the display does.
    ///
    /// Left alone, a display link on a 120 Hz iPhone is called at 60 to 80 Hz while the display
    /// refreshes faster under a scroll, and frames that are late by less than that are not
    /// seen. The range has no preferred rate, so it asks the system for nothing: on a screen
    /// that is not moving the link still runs at the rate it would have had.
    private func followDisplay() {
      // Not known before a scene is connected. The link keeps the default until then.
      guard let fastest = DeviceState.maximumFramesPerSecond(), fastest > 0 else { return }
      let range = CAFrameRateRange(
        minimum: min(Self.slowestFrameRate, Float(fastest)), maximum: Float(fastest), preferred: 0)
      if link?.preferredFrameRateRange != range { link?.preferredFrameRateRange = range }
    }

    /// The low end of the range. It only has to be below any rate a display runs at.
    private static let slowestFrameRate: Float = 8

    func stop() {
      link?.invalidate()
      link = nil
      lastTimestamp = 0
      pending = nil
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
      DeviceState.refresh()
    }

    @objc private func tick(_ link: CADisplayLink) {
      defer { lastTimestamp = link.timestamp }
      guard lastTimestamp > 0 else { return }
      let interval = (link.timestamp - lastTimestamp) * 1000
      let expected = (link.targetTimestamp - link.timestamp) * 1000
      Recorder.shared.addFrame(interval: interval, expected: max(expected, 0))
      // A recording that starts at launch begins before a scene is connected and before the
      // battery state is known. Both are there once frames are being delivered.
      framesUntilRefresh -= 1
      if framesUntilRefresh == 0 {
        DeviceState.refresh()
        followDisplay()
      }
      trackInteraction(interval: interval, timestamp: link.timestamp)
    }

    // MARK: Interactions

    func markInteraction(_ name: String, tag: String?) {
      let now = ProcessInfo.processInfo.systemUptime
      if let waited = Self.elapsed(since: TouchRecorder.lastTouchUp, now: now) {
        Recorder.shared.addSample("\(name).touchUpToHandler", tag: tag, waited * 1000)
      }
      if let waited = Self.elapsed(since: TouchRecorder.lastTouchDown, now: now) {
        Recorder.shared.addSample("\(name).touchDownToHandler", tag: tag, waited * 1000)
      }
      pending = Interaction(name: name, tag: tag)
    }

    private static func elapsed(since touch: TimeInterval, now: TimeInterval) -> TimeInterval? {
      guard touch > 0, now >= touch, now - touch <= touchValidity else { return nil }
      return now - touch
    }

    private func trackInteraction(interval: Double, timestamp: CFTimeInterval) {
      guard var current = pending else { return }
      guard let firstFrameAt = current.firstFrameAt else {
        let now = ProcessInfo.processInfo.systemUptime
        if let waited = Self.elapsed(since: TouchRecorder.lastTouchUp, now: now) {
          Recorder.shared.addSample("\(current.name).firstFrame", tag: current.tag, waited * 1000)
        }
        current.firstFrameAt = timestamp
        pending = current
        return
      }
      // The frame that crosses the end of the window counts too: a single long hitch right
      // after the interaction is exactly what this figure is for.
      current.longest = max(current.longest, interval)
      if (timestamp - firstFrameAt) * 1000 >= Hitch.interactionWindow {
        Recorder.shared.addSample(
          "\(current.name).longestFrameAfter", tag: current.tag, current.longest)
        pending = nil
      } else {
        pending = current
      }
    }

    private func installTouchRecorder() {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows
        where !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchRecorder }) {
          window.addGestureRecognizer(TouchRecorder(target: nil, action: nil))
        }
      }
    }
  }

  /// Notes when fingers land and lift anywhere in a window, without taking the touches.
  final class TouchRecorder: UIGestureRecognizer, UIGestureRecognizerDelegate {
    @MainActor static var lastTouchDown: TimeInterval = 0
    @MainActor static var lastTouchUp: TimeInterval = 0

    override init(target: Any?, action: Selector?) {
      super.init(target: target, action: action)
      cancelsTouchesInView = false
      delaysTouchesBegan = false
      delaysTouchesEnded = false
      delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      if let touch = touches.first { Self.lastTouchDown = touch.timestamp }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      if let touch = touches.first { Self.lastTouchUp = touch.timestamp }
      state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      state = .failed
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
#endif
