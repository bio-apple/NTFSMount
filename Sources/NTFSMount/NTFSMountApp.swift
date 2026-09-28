import NTFSMountCore
import SwiftUI

@main
struct NTFSMountApp: App {
  @StateObject private var store = VolumeStore()

  var body: some Scene {
    MenuBarExtra {
      MenuRoot(store: store)
    } label: {
      Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
        .help(store.menuBarTooltip)
        .onAppear { StatusItemTooltip.apply(store.menuBarTooltip) }
        .onChange(of: store.menuBarTooltip) { StatusItemTooltip.apply($0) }
    }
    .menuBarExtraStyle(.menu)
  }
}
