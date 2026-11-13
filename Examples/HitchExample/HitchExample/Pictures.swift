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
import UIKit

/// Stands in for an image pipeline: a picture takes a while to draw, and is cached once drawn.
@MainActor
final class PictureStore {
  static let shared = PictureStore()

  private let signposter = HitchSignposter(
    subsystem: "com.example.HitchExample", category: "Pictures")
  private let cache = NSCache<NSString, UIImage>()

  private init() {
    // Small, so that scrolling back up misses again and both tags keep getting figures.
    cache.countLimit = 100
  }

  /// Returns the picture of an item, drawing it when it is not cached.
  ///
  /// The length of every call is recorded under `name`, apart for hits and misses: the two
  /// share a name and nothing else.
  func picture(_ name: StaticString, for index: Int, side: CGFloat) async -> UIImage {
    // An identifier of its own, because loads of several rows overlap.
    let state = signposter.beginInterval(name, id: signposter.signposter.makeSignpostID())
    let key = "\(index)@\(Int(side))" as NSString
    if let cached = cache.object(forKey: key) {
      signposter.endInterval(name, state, tag: "hit")
      return cached
    }
    let image: UIImage
    if Catalog.drawsOnMainThread {
      image = Self.draw(index: index, side: side)
    } else {
      image = await Task.detached(priority: .userInitiated) {
        Self.draw(index: index, side: side)
      }.value
    }
    cache.setObject(image, forKey: key)
    signposter.endInterval(name, state, tag: "miss")
    return image
  }

  /// Draws overlapping discs. The same index always gives the same picture.
  nonisolated private static func draw(index: Int, side: CGFloat) -> UIImage {
    var generator = SplitMix64(seed: UInt64(index))
    let size = CGSize(width: side, height: side)
    return UIGraphicsImageRenderer(size: size).image { context in
      UIColor(
        hue: .random(in: 0...1, using: &generator), saturation: 0.5, brightness: 0.9, alpha: 1
      )
      .setFill()
      context.fill(CGRect(origin: .zero, size: size))
      for _ in 0..<discCount {
        let radius = CGFloat.random(in: side / 20...side / 4, using: &generator)
        let center = CGPoint(
          x: .random(in: 0...side, using: &generator), y: .random(in: 0...side, using: &generator))
        UIColor(
          hue: .random(in: 0...1, using: &generator), saturation: 0.7, brightness: 0.9, alpha: 0.3
        ).setFill()
        context.cgContext.fillEllipse(
          in: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      }
    }
  }

  /// Sets how long a picture takes to draw.
  nonisolated private static let discCount = 200
}

/// A small seeded generator, so that pictures do not change between runs.
private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
