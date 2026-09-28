import AppKit
import Sparkle

/// Wires Sparkle. Automatic checks stay off until the user opts in (Info.plist default).
@MainActor
final class SparkleUpdater: ObservableObject {
  static let shared = SparkleUpdater()

  private let controller: SPUStandardUpdaterController

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set {
      controller.updater.automaticallyChecksForUpdates = newValue
      objectWillChange.send()
    }
  }

  func checkForUpdates() {
    NSApp.activate(ignoringOtherApps: true)
    controller.checkForUpdates(nil)
  }
}
