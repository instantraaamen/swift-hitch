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

import os

/// A value behind a lock.
final class OSAllocatedUnfairLockBox<Value: Sendable>: Sendable {
  private let lock: OSAllocatedUnfairLock<Value>

  init(_ value: Value) {
    lock = OSAllocatedUnfairLock(initialState: value)
  }

  var value: Value {
    get { lock.withLock { $0 } }
    set { lock.withLock { $0 = newValue } }
  }
}
