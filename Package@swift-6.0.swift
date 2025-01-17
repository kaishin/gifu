// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "Gifu",
  platforms: [
    .iOS(.v16),
    .tvOS(.v16),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "Gifu",
      targets: ["Gifu"]
    )
  ],
  dependencies: [],
  targets: [
    .target(
      name: "Gifu",
      dependencies: []
    )
  ],
  swiftLanguageModes: [.v6]
)
