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
  var device: Recording.Device
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
    return Environment(
      device: device,
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
      systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      maximumFramesPerSecond: maximumFramesPerSecond
    )
  }

  @MainActor
  private static var maximumFramesPerSecond: Int? {
    #if os(iOS) || os(tvOS)
      let screens = UIApplication.shared.connectedScenes.compactMap {
        ($0 as? UIWindowScene)?.screen
      }
      return screens.map(\.maximumFramesPerSecond).max()
    #else
      return nil
    #endif
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
      batteryState: BatteryReader.state()
    )
  }
}

/// Reads the battery state from any thread. `UIDevice` is main-actor isolated, so the value is
/// kept up to date from the main actor and read from a lock.
enum BatteryReader {
  private static let cached = OSAllocatedUnfairLockBox<Recording.Conditions.BatteryState?>(nil)

  static func state() -> Recording.Conditions.BatteryState? { cached.value }

  @MainActor
  static func refresh() {
    #if os(iOS)
      switch UIDevice.current.batteryState {
      case .unplugged: cached.value = .unplugged
      case .charging: cached.value = .charging
      case .full: cached.value = .full
      case .unknown: cached.value = nil
      @unknown default: cached.value = nil
      }
    #endif
  }
}
