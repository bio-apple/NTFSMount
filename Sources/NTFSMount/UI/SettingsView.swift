import AppKit
import NTFSMountCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: VolumeStore
  @State private var logText = AppLog.tail()
  @State private var fdaStatus = FullDiskAccess.Status.unknown
  @State private var notarized = false
  @State private var developerID = false

  var body: some View {
    // Constrain ScrollView to the detail viewport so macOS can scroll instead of clipping.
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 20) {
          Text(L10n.t("settings.title"))
            .font(.title2.weight(.semibold))

          GroupBox(L10n.t("settings.mount")) {
            VStack(alignment: .leading, spacing: 10) {
              Toggle(L10n.t("settings.autoMount"), isOn: Binding(
                get: { store.autoMount },
                set: { _ in Task { await store.toggleAutoMount() } }
              ))
              .disabled(store.busyId != nil || !store.helperInstalled || Privileged.helperNeedsUpdate)
              if !store.helperInstalled || Privileged.helperNeedsUpdate {
                Text(L10n.t("settings.autoMountNeedHelper"))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Text(L10n.t("settings.autoMountNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              Toggle(L10n.t("settings.cleanMacJunk"), isOn: Binding(
                get: { store.cleanMacJunkBeforeEject },
                set: { _ in store.toggleCleanMacJunkBeforeEject() }
              ))
              Text(L10n.t("settings.cleanMacJunkNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
          }

          GroupBox(L10n.t("settings.appearance")) {
            VStack(alignment: .leading, spacing: 10) {
              Toggle(L10n.t("settings.launchAtLogin"), isOn: Binding(
                get: { store.launchAtLogin },
                set: { _ in store.toggleLogin() }
              ))
              Toggle(L10n.t("settings.showDock"), isOn: Binding(
                get: { store.showDock },
                set: { _ in store.toggleDock() }
              ))
              Text(L10n.t("settings.followsSystemLanguage"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
          }

          GroupBox(UpdateCopy.settingsGroup) {
            VStack(alignment: .leading, spacing: 10) {
              Text(UpdateCopy.autoCheckNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
          }

          GroupBox(L10n.t("settings.helper")) {
            VStack(alignment: .leading, spacing: 10) {
              Text(helperStatus)
                .font(.callout)
              HStack {
                if !Privileged.daemonReady {
                  Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("settings.install")) {
                    Task { _ = await store.installHelper() }
                  }
                  .disabled(store.helperInstallBusy)
                } else if Privileged.helperNeedsUpdate {
                  Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("settings.update")) {
                    Task { _ = await store.installHelper() }
                  }
                  .disabled(store.helperInstallBusy)
                }
                if store.helperInstalled {
                  Button(L10n.t("settings.uninstall"), role: .destructive) { store.confirmUninstallHelper() }
                    .disabled(store.helperInstallBusy)
                }
              }
              Text(helperInstallHint)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(L10n.t("helper.privilegeHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              Text(L10n.t("helper.fdaHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
          }

          GroupBox(L10n.t("settings.fda")) {
            VStack(alignment: .leading, spacing: 10) {
              Text(L10n.t("fda.body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              if fdaStatus != .unknown {
                Text(fdaStatus == .granted
                  ? L10n.t("fda.statusGranted")
                  : L10n.t("fda.statusDenied"))
                  .font(.caption)
                  .foregroundStyle(fdaStatus == .granted ? Color.secondary : Color.orange)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Text(L10n.format("fda.helperPath", FullDiskAccess.helperInstallPath))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
              Button(L10n.t("fda.open")) { FullDiskAccessSettings.openPane() }
            }
            .padding(8)
          }

          GroupBox(L10n.t("settings.aboutPrivacy")) {
            VStack(alignment: .leading, spacing: 8) {
              Text(AppVersion.line())
                .font(.headline)
              Text(UpdateCopy.settingsAboutLine)
                .font(.callout)
              Text(notarized
                ? L10n.t("settings.notarized")
                : (developerID
                  ? L10n.t("settings.signedNotNotarized")
                  : L10n.t("settings.adHoc")))
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack {
                Button(L10n.t("settings.aboutButton")) { store.showAbout() }
              }
            }
            .padding(8)
          }

          DisclosureGroup(L10n.t("settings.advanced")) {
            VStack(alignment: .leading, spacing: 16) {
              GroupBox(L10n.t("settings.compat")) {
                VStack(alignment: .leading, spacing: 8) {
                  Text(MacOSCompat.noticeBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
              }

              GroupBox(Ntfs3gVersion.settingsGroupTitle) {
                VStack(alignment: .leading, spacing: 8) {
                  Text(store.driverVersionLine)
                    .font(.callout)
                    .foregroundStyle(store.driverVersionUntested ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                  Text(Ntfs3gVersion.allowListCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
              }

              GroupBox(L10n.t("settings.log")) {
                VStack(alignment: .leading, spacing: 8) {
                  ScrollView {
                    Text(logText)
                      .font(.system(.caption, design: .monospaced))
                      .textSelection(.enabled)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .frame(minHeight: 140, maxHeight: 220)
                  HStack {
                    Button(L10n.t("settings.refreshLog")) { logText = AppLog.tail() }
                    Button(L10n.t("settings.openConsole")) { LogViewer.open() }
                  }
                }
                .padding(8)
              }
            }
            .padding(.top, 8)
          }

          if !store.message.isEmpty {
            Text(store.message)
              .font(.callout)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(width: proxy.size.width, height: max(proxy.size.height, 1), alignment: .topLeading)
    }
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      logText = AppLog.tail()
      fdaStatus = FullDiskAccess.probe()
    }
    .task {
      let notary = await Task.detached(priority: .utility) { SigningStatus.isNotarized }.value
      let dev = await Task.detached(priority: .utility) { SigningStatus.isDeveloperID }.value
      notarized = notary
      developerID = dev
    }
  }

  private var helperStatus: String {
    if !Privileged.daemonReady { return L10n.t("helper.statusMissing") }
    if Privileged.helperNeedsUpdate { return L10n.t("helper.statusNeedsUpdate") }
    if Privileged.hasLegacySudoers { return L10n.t("helper.statusLegacy") }
    return L10n.t("helper.statusOK")
  }

  private var helperInstallHint: String {
    notarized ? L10n.t("helper.hintNotarized") : L10n.t("helper.hintAdHoc")
  }
}
