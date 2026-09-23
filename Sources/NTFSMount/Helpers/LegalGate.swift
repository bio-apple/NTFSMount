import AppKit
import Foundation
import NTFSMountCore

enum LegalGate {
  @MainActor
  static func confirmOrTerminate() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: AppIdentity.Defaults.didAcceptLegal) else { return }

    NSApp.activate(ignoringOtherApps: true)
    let notarized = SigningStatus.isNotarized
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = OnboardingCopy.messageTitle
    alert.informativeText = OnboardingCopy.body(notarized: notarized)
    alert.addButton(withTitle: OnboardingCopy.quitTitle)
    alert.addButton(withTitle: OnboardingCopy.agreeTitle)
    if let quit = alert.buttons.first {
      quit.keyEquivalent = "\r"
    }
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = ""
    }
    if alert.runModal() != .alertSecondButtonReturn {
      NSApp.terminate(nil)
      return
    }
    d.set(true, forKey: AppIdentity.Defaults.didAcceptLegal)
    if !notarized {
      d.set(true, forKey: AppIdentity.Defaults.didShowGatekeeper)
    }
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
    alert.messageText = "以可写方式挂载？"
    alert.informativeText = "第三方驱动写 NTFS 可能损坏卷上的文件。请确认重要数据已备份。此提示只出现一次。"
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "已备份，继续")
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
}
