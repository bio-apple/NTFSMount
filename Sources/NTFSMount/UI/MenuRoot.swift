import AppKit
import NTFSMountCore
import SwiftUI

struct MenuRoot: View {
  @ObservedObject var store: VolumeStore

  var body: some View {
    Button(L10n.t("menu.openWindow")) { store.showMainWindow() }
      .keyboardShortcut("o")
    if !store.helperInstalled || !Privileged.daemonReady {
      Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("menu.installHelper")) {
        Task { _ = await store.installHelper() }
      }
      .disabled(store.helperInstallBusy)
    } else if Privileged.helperNeedsUpdate {
      Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("menu.updateHelper")) {
        Task { _ = await store.installHelper() }
      }
      .disabled(store.helperInstallBusy)
    }
    Divider()
    if store.volumes.isEmpty {
      Text(L10n.t("menu.noNTFS"))
      Text(store.formatDisks.isEmpty
        ? L10n.t("menu.insertHint")
        : L10n.t("menu.formatOtherHint"))
        .foregroundStyle(.secondary)
      ForEach(store.encryptedDisks) { disk in
        Text(L10n.format("menu.encryptedLine", disk.name))
          .foregroundStyle(.secondary)
      }
    } else {
      ForEach(store.volumes) { vol in
        Menu {
          ForEach(Array(store.diskStatusRows(vol).enumerated()), id: \.offset) { _, row in
            Text(row.line)
          }
          Divider()
          if store.canOfferDirtyFix(vol) {
            Button(L10n.t("menu.fixDirty")) {
              Task { await store.confirmDirtyFix(vol) }
            }
            .disabled(store.busyId != nil)
          }
          if !vol.isWritableFuse {
            Button(vol.isInternal ? L10n.t("menu.mountWritableInternal") : L10n.t("menu.mountWritable")) {
              Task { await store.mount(vol) }
            }
            .disabled(store.busyId != nil || !store.canMountWritable(vol))
            .help(store.helperInstalled ? store.writableMountHelp(vol) : L10n.t("menu.needHelper"))
          }
          Button(L10n.t("menu.openFinder")) {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
          .disabled(vol.mountPoint.isEmpty)
          Divider()
          Button(L10n.t("menu.unmount")) { Task { await store.unmount(vol) } }
            .disabled(vol.mountPoint.isEmpty || store.busyId != nil)
            .help(VolumeActionCopy.unmountHelp)
          if !vol.isInternal {
            Button(L10n.t("menu.eject")) { Task { await store.eject(vol) } }
              .disabled(store.busyId != nil)
              .help(VolumeActionCopy.ejectHelp)
          }
        } label: {
          HStack(spacing: 6) {
            if store.busyId == vol.id {
              ProgressView()
                .controlSize(.small)
            }
            Text("\(store.statusLabel(vol))  ·  \(vol.name)  ·  \(vol.sizeLabel)")
          }
          .help(MenuBarTooltip.card(vol))
        }
      }
      Divider()
      Button(L10n.t("menu.mountAll")) { store.mountAll() }
        .keyboardShortcut("m")
        .disabled(
          !store.helperInstalled
            || store.volumes.filter({ !$0.isInternal }).allSatisfy(\.isWritableFuse)
            || store.busyId != nil
        )
        .help(store.helperInstalled ? L10n.t("menu.mountAllHelp") : L10n.t("menu.needHelper"))
    }
    if !store.formatDisks.isEmpty {
      Divider()
      Menu(L10n.t("menu.formatNTFS")) {
        ForEach(store.formatDisks) { disk in
          Button(L10n.format("menu.formatItem", disk.name, disk.fsHint, disk.sizeLabel), role: .destructive) {
            store.confirmFormat(disk)
          }
          .disabled(store.busyId != nil)
          .help(disk.encryptionWarning ?? L10n.t("menu.eraseWholeDisk"))
        }
      }
    }
    Divider()
    Button(L10n.t("menu.refresh")) { store.refresh() }
      .keyboardShortcut("r")
    Button(L10n.t("menu.diagnose")) { EnvironmentDiagnosePresenter.present(store: store) }
    Button(L10n.t("menu.exportDiagnose")) { EnvironmentDiagnosePresenter.exportReport(store: store) }
    Button(L10n.t("menu.settings")) { store.showSettings() }
    Button(AppVersion.menuTitle()) { store.showAbout() }
    if !store.message.isEmpty {
      Text(store.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    Divider()
    Button(L10n.t("menu.quitApp")) { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
