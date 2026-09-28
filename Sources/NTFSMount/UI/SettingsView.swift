import AppKit
import NTFSMountCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: VolumeStore
  @ObservedObject private var updater = SparkleUpdater.shared
  @State private var logText = AppLog.tail()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(L10n.t("settings.title"))
          .font(.title2.weight(.semibold))

        GroupBox(L10n.t("settings.mount")) {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.t("settings.autoMount"), isOn: Binding(
              get: { store.autoMount },
              set: { _ in store.toggleAutoMount() }
            ))
            .disabled(store.busyId != nil || !store.helperInstalled || Privileged.helperNeedsUpdate)
            Text(L10n.t("settings.autoMountNote"))
              .font(.caption)
              .foregroundStyle(.secondary)
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
            Toggle(UpdateCopy.autoCheckToggle, isOn: Binding(
              get: { updater.automaticallyChecksForUpdates },
              set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            Text(UpdateCopy.autoCheckNote)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button(UpdateCopy.checkNow) { updater.checkForUpdates() }
          }
          .padding(8)
        }

        GroupBox(L10n.t("settings.helper")) {
          VStack(alignment: .leading, spacing: 10) {
            Text(helperStatus)
              .font(.callout)
            HStack {
              if !store.helperInstalled {
                Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("settings.install")) {
                  store.installHelper()
                }
                .disabled(store.helperInstallBusy)
              } else if Privileged.helperNeedsUpdate {
                Button(store.helperInstallBusy ? L10n.t("installing") : L10n.t("settings.update")) {
                  store.installHelper()
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
          }
          .padding(8)
        }

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
              Button(L10n.t("menu.diagnose")) { EnvironmentDiagnosePresenter.present() }
            }
            Text(L10n.t("settings.diagnoseHint"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
        }

        GroupBox(L10n.t("settings.aboutPrivacy")) {
          VStack(alignment: .leading, spacing: 8) {
            Text(UpdateCopy.settingsAboutLine)
              .font(.callout)
            Text(SigningStatus.isNotarized
              ? L10n.t("settings.notarized")
              : (SigningStatus.isDeveloperID
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

        if !store.message.isEmpty {
          Text(store.message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .padding(28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { logText = AppLog.tail() }
  }

  private var helperStatus: String {
    if !store.helperInstalled { return L10n.t("helper.statusMissing") }
    if Privileged.helperNeedsUpdate { return L10n.t("helper.statusNeedsUpdate") }
    if Privileged.hasLegacySudoers { return L10n.t("helper.statusLegacy") }
    return L10n.t("helper.statusOK")
  }

  private var helperInstallHint: String {
    if SigningStatus.isNotarized {
      return L10n.t("helper.hintNotarized")
    }
    return L10n.t("helper.hintAdHoc")
  }
}
