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
import HitchRecording

#if canImport(UIKit) && !os(watchOS)
  import UIKit
#endif

/// What the recorder knows about where it is running.
struct Environment: Sendable {
  /// The device. The display's refresh rate is only known once a scene is connected, which
  /// is after a recording that starts at launch has begun, so this is read at every write.
  var device: @Sendable () -> Recording.Device
  var app: Recording.App
  var secondsSinceLaunch: Double?
  var conditions: @Sendable () -> Recording.Conditions

  /// Reads the environment of the current process. Call it once, when a recording starts.
  @MainActor
  static func current() -> Environment {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
      // Battery state is only reported while monitoring is on.
      UIDevice.current.isBatteryMonitoringEnabled = true
    #endif
    DeviceState.refresh()
    let device = device
    return Environment(
      device: {
        var device = device
        device.maximumFramesPerSecond = DeviceState.maximumFramesPerSecond()
        return device
      },
      app: app,
      secondsSinceLaunch: secondsSinceLaunch(),
      conditions: { currentConditions() }
    )
  }

  @MainActor
  private static var device: Recording.Device {
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
    #elseif os(visionOS)
      let systemName = "visionOS"
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

  private static var app: Recording.App {
    let info = Bundle.main.infoDictionary ?? [:]
    #if DEBUG
      let configuration = Recording.App.Configuration.debug
    #else
      let configuration = Recording.App.Configuration.release
    #endif
    return Recording.App(
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
      version: info["CFBundleShortVersionString"] as? String ?? "",
      build: info["CFBundleVersion"] as? String ?? "",
      configuration: configuration
    )
  }

  /// How long ago the process was started, from the kernel's record of it.
  private static func secondsSinceLaunch() -> Double? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return nil }
    let started = info.kp_proc.p_starttime
    let startedAt = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
    let elapsed = Date().timeIntervalSince1970 - startedAt
    return elapsed >= 0 ? elapsed : nil
  }

  private static func currentConditions() -> Recording.Conditions {
    let thermalState: Recording.Conditions.ThermalState
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: thermalState = .nominal
    case .fair: thermalState = .fair
    case .serious: thermalState = .serious
    case .critical: thermalState = .critical
    @unknown default: thermalState = .nominal
    }
    #if os(macOS)
      let isLowPowerModeEnabled: Bool
      if #available(macOS 12.0, *) {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
      } else {
        isLowPowerModeEnabled = false
      }
    #else
      let isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    #endif
    return Recording.Conditions(
      thermalState: thermalState,
      isLowPowerModeEnabled: isLowPowerModeEnabled,
      batteryState: DeviceState.batteryState()
    )
  }
}

/// What `UIKit` knows about the device, readable from any thread.
///
/// `UIDevice` and `UIScreen` are main-actor isolated, and neither has an answer at launch: the
/// battery state is unknown until monitoring has run for a moment, and there is no screen until
/// a scene connects. The values are refreshed from the main actor whenever the app becomes
/// active, and read from a lock.
enum DeviceState {
  private struct Values: Sendable {
    var batteryState: Recording.Conditions.BatteryState?
    var maximumFramesPerSecond: Int?
  }

  private static let values = OSAllocatedUnfairLockBox(Values())

  static func batteryState() -> Recording.Conditions.BatteryState? { values.value.batteryState }
  static func maximumFramesPerSecond() -> Int? { values.value.maximumFramesPerSecond }

  @MainActor
  static func refresh() {
    var current = values.value
    #if os(iOS)
      switch UIDevice.current.batteryState {
      case .unplugged: current.batteryState = .unplugged
      case .charging: current.batteryState = .charging
      case .full: current.batteryState = .full
      case .unknown: break
      @unknown default: break
      }
    #endif
    #if os(iOS) || os(tvOS)
      let screens = UIApplication.shared.connectedScenes.compactMap {
        ($0 as? UIWindowScene)?.screen
      }
      if let fastest = screens.map(\.maximumFramesPerSecond).max() {
        current.maximumFramesPerSecond = fastest
      }
    #endif
    values.value = current
  }
}
