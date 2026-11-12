#if os(iOS) || os(tvOS)
  import UIKit

  /// Watches the display link on the main run loop.
  ///
  /// A late callback means the main thread was busy when the display asked for a frame. Work
  /// that is late on the render server alone does not show up here; use Instruments for that.
  @MainActor
  final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var pending: (name: String, frames: Int, longest: Double)?

    /// How many frames after an interaction are inspected.
    private static let framesAfterInteraction = 30

    func start() {
      guard link == nil else { return }
      let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
      link.add(to: .main, forMode: .common)
      self.link = link

      let center = NotificationCenter.default
      observers = [
        // The display link pauses in the background. Without this, the first frame after
        // coming back would be recorded as a hitch that lasted the whole absence.
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated {
            self?.lastTimestamp = 0
            self?.installTouchRecorder()
          }
        },
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
          _ in Recorder.shared.flush()
        },
      ]
      installTouchRecorder()
    }

    func stop() {
      link?.invalidate()
      link = nil
      lastTimestamp = 0
      pending = nil
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
    }

    @objc private func tick(_ link: CADisplayLink) {
      defer { lastTimestamp = link.timestamp }
      guard lastTimestamp > 0 else { return }
      let interval = (link.timestamp - lastTimestamp) * 1000
      let expected = (link.targetTimestamp - link.timestamp) * 1000
      Recorder.shared.addFrame(interval: interval, expected: max(expected, 0))
      trackInteraction(interval: interval)
    }

    // MARK: Interactions

    func markInteraction(_ name: String) {
      let now = ProcessInfo.processInfo.systemUptime
      if TouchRecorder.lastTouchUp > 0 {
        Recorder.shared.addSample("\(name).touchUpToHandler", (now - TouchRecorder.lastTouchUp) * 1000)
      }
      if TouchRecorder.lastTouchDown > 0 {
        Recorder.shared.addSample("\(name).touchDownToHandler", (now - TouchRecorder.lastTouchDown) * 1000)
      }
      pending = (name, 0, 0)
    }

    private func trackInteraction(interval: Double) {
      guard var current = pending else { return }
      if current.frames == 0 {
        if TouchRecorder.lastTouchUp > 0 {
          let now = ProcessInfo.processInfo.systemUptime
          Recorder.shared.addSample("\(current.name).firstFrame", (now - TouchRecorder.lastTouchUp) * 1000)
        }
      } else {
        current.longest = max(current.longest, interval)
      }
      current.frames += 1
      if current.frames > Self.framesAfterInteraction {
        Recorder.shared.addSample("\(current.name).longestFrameAfter", current.longest)
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
