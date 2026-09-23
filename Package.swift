// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "NTFSMount",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "NTFSMount", targets: ["NTFSMount"]),
    .library(name: "NTFSMountCore", targets: ["NTFSMountCore"]),
  ],
  targets: [
    .target(
      name: "NTFSMountCore",
      path: "Sources/NTFSMountCore"
    ),
    .executableTarget(
      name: "NTFSMount",
      dependencies: ["NTFSMountCore"],
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
