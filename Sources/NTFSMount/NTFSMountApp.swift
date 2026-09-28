import NTFSMountCore
import SwiftUI
import os

@main
struct NTFSMountApp: App {
  @StateObject private var store = VolumeStore()

  init() {
    AppLog.app.info("start helperVersion=\(AppIdentity.helperVersion, privacy: .public)")
  }

  var body: some Scene {
    MenuBarExtra {
      MenuRoot(store: store)
    } label: {
      Group {
        if store.busyId != nil || store.helperInstallBusy {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
        }
      }
      .help(store.menuBarTooltip)
      .onAppear { StatusItemTooltip.apply(store.menuBarTooltip) }
      .onChange(of: store.menuBarTooltip) { StatusItemTooltip.apply($0) }
    }
    .menuBarExtraStyle(.menu)
  }
}
