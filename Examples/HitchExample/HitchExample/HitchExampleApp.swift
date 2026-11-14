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

import Hitch
import SwiftUI

@main
struct HitchExampleApp: App {
  init() {
    // Records only when the app was launched with `--hitch-record`, which `hitch record` does.
    // An app that ships would put this behind `#if DEBUG`.
    Hitch.startIfRequested(metadata: ["itemCount": "\(Catalog.itemCount)"])
  }

  var body: some Scene {
    WindowGroup {
      ItemList()
    }
  }
}

enum Catalog {
  /// How many rows the list holds. Stored with the recording, so that recordings made with
  /// different amounts of data are not compared by accident.
  static let itemCount = 2000

  /// Launch with `--slow` to draw every picture on the main thread. That is the "before" of
  /// the comparison this example is for.
  static let drawsOnMainThread = ProcessInfo.processInfo.arguments.contains("--slow")
}
