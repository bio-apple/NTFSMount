import Sparkle

/// Unnotarized personal-use builds do not start Sparkle.
/// Users download a DMG from GitHub Releases. The framework stays linked for later notarized builds.
@MainActor
final class SparkleUpdater: ObservableObject {
  static let shared = SparkleUpdater()

  /// Keeps Sparkle.framework linked without constructing or starting an updater.
  private let sparkleControllerType: SPUStandardUpdaterController.Type = SPUStandardUpdaterController.self

  private init() {
    _ = sparkleControllerType
  }

  func checkForUpdates() {}
}
