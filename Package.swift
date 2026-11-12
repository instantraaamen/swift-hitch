// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-hitch",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
  ],
  products: [
    .library(name: "Hitch", targets: ["Hitch"]),
    .executable(name: "hitch", targets: ["HitchCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
  ],
  targets: [
    .target(name: "Hitch"),
    .executableTarget(
      name: "HitchCLI",
      dependencies: [
        "Hitch",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "HitchTests", dependencies: ["Hitch"]),
  ]
)
