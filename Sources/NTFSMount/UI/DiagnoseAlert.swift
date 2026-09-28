import AppKit
import NTFSMountCore

/// NSAlert for read-only diagnose. Copy / reveal log; never install helper.
enum EnvironmentDiagnosePresenter {
  private static var busy = false

  @MainActor
  static func present() {
    guard !busy else { return }
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let snap = EnvironmentDiagnoseRunner.snapshot()
      let lines = EnvironmentDiagnose.lines(from: snap)
      let text = EnvironmentDiagnose.reportText(from: lines)
      AppLog.append("diagnose\n\(text)")
      DispatchQueue.main.async {
        busy = false
        showAlert(text)
      }
    }
  }

  @MainActor
  private static func showAlert(_ text: String) {
    NSApp.activate(ignoringOtherApps: true)
    while true {
      let alert = NSAlert()
      alert.messageText = L10n.t("diagnose.alertTitle")
      alert.informativeText = text
      alert.addButton(withTitle: L10n.t("ok.gotIt"))
      alert.addButton(withTitle: L10n.t("diagnose.copy"))
      alert.addButton(withTitle: L10n.t("diagnose.openLog"))
      switch alert.runModal() {
      case .alertSecondButtonReturn:
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      case .alertThirdButtonReturn:
        LogViewer.open()
        return
      default:
        return
      }
    }
  }
}
