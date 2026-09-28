import NTFSMountCore
import SwiftUI

@main
struct NTFSMountApp: App {
  @StateObject private var store = VolumeStore()

  init() {
    _ = SparkleUpdater.shared
  }

  var body: some Scene {
    MenuBarExtra {
      MenuRoot(store: store)
    } label: {
      Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
    }
    .menuBarExtraStyle(.menu)
  }
}
