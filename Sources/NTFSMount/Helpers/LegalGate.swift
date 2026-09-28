import AppKit
import Foundation
import NTFSMountCore

enum LegalGate {
  @MainActor
  static var hasAcceptedLegal: Bool {
    let d = UserDefaults.standard
    return d.bool(forKey: AppIdentity.Defaults.didAcceptLegal)
      && d.integer(forKey: AppIdentity.Defaults.didAcceptLegalVersion) == OnboardingCopy.copyVersion
  }

  @MainActor
  static func confirmOrTerminate() {
    let d = UserDefaults.standard
    if hasAcceptedLegal { return }

    NSApp.activate(ignoringOtherApps: true)
    let notarized = SigningStatus.isNotarized
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = OnboardingCopy.messageTitle
    alert.informativeText = OnboardingCopy.body(notarized: notarized)
    alert.addButton(withTitle: OnboardingCopy.agreeTitle)
    alert.addButton(withTitle: OnboardingCopy.quitTitle)
    if let agree = alert.buttons.first {
      agree.keyEquivalent = "\r"
    }
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = "\u{1b}"
    }
    if alert.runModal() != .alertFirstButtonReturn {
      NSApp.terminate(nil)
      return
    }
    d.set(true, forKey: AppIdentity.Defaults.didAcceptLegal)
    d.set(OnboardingCopy.copyVersion, forKey: AppIdentity.Defaults.didAcceptLegalVersion)
    if !notarized {
      showGatekeeperNote()
      d.set(true, forKey: AppIdentity.Defaults.didShowGatekeeper)
    }
  }

  @MainActor
  static func showGatekeeperNote() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = OnboardingCopy.gatekeeperTitle
    alert.informativeText = OnboardingCopy.gatekeeperBody
    alert.addButton(withTitle: L10n.t("ok.gotIt"))
    alert.runModal()
  }

  @MainActor
  static func confirmWritable() -> Bool {
    if UserDefaults.standard.bool(forKey: AppIdentity.Defaults.didAcceptWritable),
       FileManager.default.fileExists(atPath: AppIdentity.writableStampURL.path) {
      return true
    }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.t("writable.title")
    alert.informativeText = L10n.t("writable.body")
    alert.addButton(withTitle: L10n.t("cancel"))
    alert.addButton(withTitle: L10n.t("writable.continue"))
    if let cancel = alert.buttons.first {
      cancel.keyEquivalent = "\r"
    }
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = ""
    }
    guard alert.runModal() == .alertSecondButtonReturn else { return false }
    AppIdentity.markWritableAccepted()
    return true
  }

  /// 未经测试的捆绑 ntfs-3g：一次性警告，用户可继续。不硬拦挂载。
  @MainActor
  static func confirmUntestedDriver(_ parsed: Ntfs3gVersion.Parsed) -> Bool {
    guard parsed.status == .untested else { return true }
    let key = AppIdentity.Defaults.acceptedUntestedNtfs3g
    if UserDefaults.standard.string(forKey: key) == parsed.displayVersion {
      return true
    }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = Ntfs3gVersion.mountWarningTitle
    alert.informativeText = Ntfs3gVersion.mountWarningBody(parsed)
    alert.addButton(withTitle: Ntfs3gVersion.cancelTitle)
    alert.addButton(withTitle: Ntfs3gVersion.continueTitle)
    if let cancel = alert.buttons.first {
      cancel.keyEquivalent = "\r"
    }
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = ""
    }
    guard alert.runModal() == .alertSecondButtonReturn else { return false }
    UserDefaults.standard.set(parsed.displayVersion, forKey: key)
    return true
  }
}
