// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "NTFSMount",
  defaultLocalization: "zh-Hans",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "NTFSMount", targets: ["NTFSMount"]),
    .library(name: "NTFSMountCore", targets: ["NTFSMountCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
  ],
  targets: [
    .target(
      name: "NTFSMountCore",
      path: "Sources/NTFSMountCore",
      resources: [
        .process("Resources"),
      ]
    ),
    .executableTarget(
      name: "NTFSMount",
      dependencies: [
        "NTFSMountCore",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/NTFSMount",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("SwiftUI"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("DiskArbitration"),
      ]
    ),
    .testTarget(
      name: "NTFSMountCoreTests",
      dependencies: ["NTFSMountCore"],
      path: "Tests/NTFSMountCoreTests"
    ),
  ]
)
