// swift-tools-version: 6.0
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

import PackageDescription

let package = Package(
  name: "swift-hitch",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
    .visionOS(.v1),
  ],
  products: [
    // Goes into the app: records frame pacing and durations while a person uses it.
    .library(name: "Hitch", targets: ["Hitch"]),
    // The recording file format, for tools that read recordings.
    .library(name: "HitchRecording", targets: ["HitchRecording"]),
    // Statistics and before/after comparison, for tools. Not needed in the app.
    .library(name: "HitchAnalysis", targets: ["HitchAnalysis"]),
    .executable(name: "hitch", targets: ["HitchCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
  ],
  targets: [
    .target(name: "HitchRecording"),
    .target(name: "Hitch", dependencies: ["HitchRecording"]),
    .target(name: "HitchAnalysis", dependencies: ["HitchRecording"]),
    .executableTarget(
      name: "HitchCLI",
      dependencies: [
        "HitchAnalysis",
        "HitchRecording",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "HitchTests", dependencies: ["Hitch", "HitchRecording"]),
    .testTarget(name: "HitchAnalysisTests", dependencies: ["HitchAnalysis", "HitchRecording"]),
    .testTarget(
      name: "HitchCLITests", dependencies: ["HitchCLI", "HitchAnalysis", "HitchRecording"]),
  ]
)
