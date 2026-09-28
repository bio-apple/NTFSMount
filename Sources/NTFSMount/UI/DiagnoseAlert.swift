import AppKit
import NTFSMountCore
import os

/// Scrollable diagnose window. Scan is read-only (never installs). After the report,
/// the user can repair leftover NTFSMount mounts or install the mount helper.
enum EnvironmentDiagnosePresenter {
  @MainActor
  static func present(store: VolumeStore) {
    DiagnoseWindowController.shared.show(store: store)
  }

  @MainActor
  static func exportReport(store: VolumeStore) {
    DiagnoseWindowController.shared.exportReport(store: store)
  }
}

@MainActor
final class DiagnoseWindowController: NSObject, NSWindowDelegate {
  static let shared = DiagnoseWindowController()

  private var window: NSWindow?
  private var textView: NSTextView?
  private var spinner: NSProgressIndicator?
  private var copyButton: NSButton?
  private var exportButton: NSButton?
  private var repairButton: NSButton?
  private var installButton: NSButton?
  private var hintField: NSTextField?
  private var hintCollapse: NSLayoutConstraint?
  private var buttonRow: NSStackView?
  private weak var store: VolumeStore?
  private var running = false
  private var installing = false
  private var repairing = false
  private var exporting = false
  private var report = ""
  private var lastSnap: DiagnoseSnapshot?
  private var generation = 0

  func show(store: VolumeStore) {
    self.store = store
    if window == nil {
      buildWindow()
    }
    Privileged.prepareForAdminPrompt()
    window?.makeKeyAndOrderFront(nil)
    if !running && !installing && !repairing && !exporting {
      start()
    }
  }

  func windowWillClose(_ notification: Notification) {
    running = false
    DispatchQueue.main.async {
      let othersVisible = NSApp.windows.contains { $0.isVisible && $0 != self.window }
      if !othersVisible && !UserDefaults.standard.bool(forKey: AppIdentity.Defaults.showDock) {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  private func start() {
    generation += 1
    let token = generation
    running = true
    installing = false
    repairing = false
    report = ""
    setBody(L10n.t("diagnose.checking"))
    spinner?.startAnimation(nil)
    spinner?.isHidden = false
    copyButton?.isEnabled = false
    exportButton?.isEnabled = false
    setHint(nil)
    setInstallVisible(false)
    updateRepairButton()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let snap = EnvironmentDiagnoseRunner.snapshot()
      let lines = EnvironmentDiagnose.lines(from: snap)
      let text = EnvironmentDiagnose.reportText(from: lines)
      AppLog.append("diagnose\n\(text)", unified: false)
      AppLog.diagnose.info("diagnose completed")
      DispatchQueue.main.async {
        guard let self, self.generation == token else { return }
        self.running = false
        self.report = text
        self.lastSnap = snap
        self.setBody(text)
        self.spinner?.stopAnimation(nil)
        self.spinner?.isHidden = true
        self.copyButton?.isEnabled = true
        self.exportButton?.isEnabled = true
        self.updateActions(snap)
      }
    }
  }

  private func updateActions(_ snap: DiagnoseSnapshot) {
    if EnvironmentDiagnose.bundledComponentsBroken(snap) {
      setHint(L10n.t("diagnose.brokenBundle"))
    } else {
      setHint(L10n.t("diagnose.exportHint"))
    }

    let helperOffer = EnvironmentDiagnose.helperNeedsInstall(snap)
      || Privileged.helperNeedsUpdate
    setInstallVisible(helperOffer)
    updateRepairButton()
    guard helperOffer else { return }
    let update = Privileged.helperOfferIsUpdate
    installButton?.title = L10n.t(update ? "diagnose.updateHelper" : "diagnose.installHelper")
    installButton?.isEnabled = !(store?.helperInstallBusy ?? false) && !installing
  }

  private func setHint(_ text: String?) {
    let show = !(text ?? "").isEmpty
    hintField?.stringValue = text ?? ""
    hintField?.isHidden = !show
    hintCollapse?.isActive = !show
  }

  private func updateRepairButton() {
    guard let repair = repairButton else { return }
    repair.title = repairing ? L10n.t("repairEnv.working") : L10n.t("menu.repairEnv")
    let helperReady = store?.helperInstalled == true
    repair.isEnabled = helperReady
      && !repairing
      && !running
      && !installing
      && !exporting
      && !(store?.helperInstallBusy ?? false)
      && store?.busyId == nil
  }

  private func setInstallVisible(_ visible: Bool) {
    guard let install = installButton else { return }
    install.isHidden = !visible
    buttonRow?.setVisibilityPriority(visible ? .mustHold : .notVisible, for: install)
  }

  private func setBody(_ text: String) {
    textView?.string = text
  }

  @objc private func copyReport() {
    let text = report.isEmpty ? (textView?.string ?? "") : report
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  @objc private func exportClicked() {
    exportReport()
  }

  @objc private func installHelper() {
    guard !installing else { return }
    guard let store else {
      showInstallFailure(L10n.t("diagnose.installFailed"))
      return
    }
    guard !store.helperInstallBusy else { return }
    Privileged.prepareForAdminPrompt()
    window?.makeKeyAndOrderFront(nil)
    installing = true
    installButton?.title = L10n.t("installing")
    installButton?.isEnabled = false
    Task { @MainActor [weak self] in
      guard let self, let store = self.store else { return }
      let outcome = await store.installHelper()
      self.installing = false
      guard self.window?.isVisible == true else { return }
      if outcome.ok, Privileged.daemonReady {
        self.start()
      } else {
        if let snap = self.lastSnap {
          self.updateActions(snap)
        } else {
          self.installButton?.isEnabled = true
        }
        self.showInstallFailure(outcome.text)
      }
    }
  }

  @objc private func repairEnv() {
    guard !repairing, !installing, !running else { return }
    guard let store else { return }
    Privileged.prepareForAdminPrompt()
    window?.makeKeyAndOrderFront(nil)
    let started = store.confirmRepairMountEnvironment { [weak self] outcome in
      guard let self else { return }
      self.repairing = false
      guard self.window?.isVisible == true else { return }
      if outcome.ok {
        self.start()
      } else {
        self.showRepairResult(outcome.text)
        if let snap = self.lastSnap {
          self.updateActions(snap)
        } else {
          self.updateRepairButton()
        }
      }
    }
    guard started else {
      updateRepairButton()
      return
    }
    repairing = true
    updateRepairButton()
    spinner?.startAnimation(nil)
    spinner?.isHidden = false
  }

  private func showRepairResult(_ detail: String) {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    var block = "\n\n—— \(L10n.t("repairEnv.failed")) ——\n"
    if !trimmed.isEmpty {
      block += trimmed + "\n"
    }
    let body = report.isEmpty ? block.trimmingCharacters(in: .whitespacesAndNewlines) : report + block
    report = body
    setBody(body)
    copyButton?.isEnabled = true
    exportButton?.isEnabled = true
    spinner?.stopAnimation(nil)
    spinner?.isHidden = true
    setHint(trimmed.split(whereSeparator: \.isNewline).first.map(String.init))
  }

  private func showInstallFailure(_ detail: String) {
    let shown = UserFacingError.message(from: detail, logPath: AppLog.url.path)
    let logs = AppLog.tail(40)
    var block = "\n\n—— \(L10n.t("diagnose.installFailed")) ——\n"
    if !shown.isEmpty {
      block += shown + "\n"
    }
    block += "\n\(AppLog.url.path)\n\(logs)"
    let body = report.isEmpty ? block.trimmingCharacters(in: .whitespacesAndNewlines) : report + block
    report = body
    setBody(body)
    copyButton?.isEnabled = true
    exportButton?.isEnabled = true
    let hint = shown.split(whereSeparator: \.isNewline).first.map(String.init)
    setHint(hint)
  }

  func exportReport(store: VolumeStore? = nil) {
    if let store {
      self.store = store
    }
    guard let store = self.store else { return }
    guard !exporting, !running else { return }
    DiagnoseReportExporter.beginExport(
      store: store,
      snap: lastSnap,
      report: report,
      sheetWindow: window,
      onStart: { [weak self] in
        self?.beginExportProgress()
      },
      onFinish: { [weak self] result in
        self?.finishExport(result)
      }
    )
  }

  private func beginExportProgress() {
    exporting = true
    exportButton?.isEnabled = false
    setHint(L10n.t("diagnose.exporting"))
    spinner?.startAnimation(nil)
    spinner?.isHidden = false
    AppLog.diagnose.info("diagnose export started")
  }

  private func finishExport(_ result: Result<URL, Error>) {
    exporting = false
    exportButton?.isEnabled = lastSnap != nil || !report.isEmpty
    spinner?.stopAnimation(nil)
    spinner?.isHidden = true
    switch result {
    case .success(let url):
      setHint(L10n.format("diagnose.exportSaved", url.path))
      AppLog.diagnose.info("diagnose export saved")
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .failure(let error):
      let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      setHint(L10n.format("diagnose.exportFailed", detail))
      AppLog.diagnose.error("diagnose export failed")
      if window?.isVisible != true {
        let alert = NSAlert()
        alert.messageText = L10n.t("diagnose.export")
        alert.informativeText = L10n.format("diagnose.exportFailed", detail)
        alert.addButton(withTitle: L10n.t("ok.gotIt"))
        alert.runModal()
      }
    }
  }

  @objc private func closeWindow() {
    window?.close()
  }

  private func buildWindow() {
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    win.title = L10n.t("diagnose.alertTitle")
    win.minSize = NSSize(width: 480, height: 340)
    win.isReleasedWhenClosed = false
    win.delegate = self
    win.center()

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 480))

    let spinner = NSProgressIndicator()
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false

    let scroll = NSTextView.scrollableTextView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.borderType = .bezelBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false

    let text = scroll.documentView as? NSTextView ?? NSTextView()
    text.isEditable = false
    text.isSelectable = true
    text.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    text.textContainerInset = NSSize(width: 8, height: 8)
    text.string = L10n.t("diagnose.checking")

    let hint = NSTextField(wrappingLabelWithString: "")
    hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    hint.textColor = NSColor.secondaryLabelColor
    hint.translatesAutoresizingMaskIntoConstraints = false
    hint.isHidden = true
    hint.preferredMaxLayoutWidth = 560
    hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let chrome = makeButtonChrome()
    content.addSubview(spinner)
    content.addSubview(scroll)
    content.addSubview(hint)
    content.addSubview(chrome.column)

    let hintCollapse = hint.heightAnchor.constraint(equalToConstant: 0)
    hintCollapse.isActive = true

    NSLayoutConstraint.activate([
      spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      spinner.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      scroll.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
      scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
      hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      hint.bottomAnchor.constraint(equalTo: chrome.column.topAnchor, constant: -12),
      chrome.column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      chrome.column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      chrome.column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
      chrome.shareRow.widthAnchor.constraint(equalTo: chrome.column.widthAnchor),
      chrome.actionRow.widthAnchor.constraint(equalTo: chrome.column.widthAnchor),
    ])

    win.contentView = content
    self.window = win
    self.textView = text
    self.spinner = spinner
    self.copyButton = chrome.copy
    self.exportButton = chrome.export
    self.repairButton = chrome.repair
    self.installButton = chrome.install
    self.hintField = hint
    self.hintCollapse = hintCollapse
    self.buttonRow = chrome.actionRow
  }

  private struct ButtonChrome {
    let copy: NSButton
    let export: NSButton
    let repair: NSButton
    let install: NSButton
    let shareRow: NSStackView
    let actionRow: NSStackView
    let column: NSStackView
  }

  private func makeButtonChrome() -> ButtonChrome {
    let copy = NSButton(title: L10n.t("diagnose.copy"), target: self, action: #selector(copyReport))
    copy.bezelStyle = .rounded
    copy.isEnabled = false

    let export = NSButton(
      title: L10n.t("diagnose.export"),
      target: self,
      action: #selector(exportClicked)
    )
    export.bezelStyle = .rounded
    export.isEnabled = false

    let repair = NSButton(
      title: L10n.t("menu.repairEnv"),
      target: self,
      action: #selector(repairEnv)
    )
    repair.bezelStyle = .rounded

    let install = NSButton(
      title: L10n.t("diagnose.installHelper"),
      target: self,
      action: #selector(installHelper)
    )
    install.bezelStyle = .rounded
    install.isHidden = true

    let close = NSButton(title: L10n.t("ok.gotIt"), target: self, action: #selector(closeWindow))
    close.bezelStyle = .rounded
    close.keyEquivalent = "\r"

    let spacer = NSView()
    spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)

    let shareRow = NSStackView(views: [copy, export])
    shareRow.orientation = .horizontal
    shareRow.alignment = .centerY
    shareRow.spacing = 12

    let actionRow = NSStackView(views: [repair, install, spacer, close])
    actionRow.orientation = .horizontal
    actionRow.alignment = .centerY
    actionRow.spacing = 12
    actionRow.setVisibilityPriority(.notVisible, for: install)

    let column = NSStackView(views: [shareRow, actionRow])
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 8
    column.translatesAutoresizingMaskIntoConstraints = false

    return ButtonChrome(
      copy: copy,
      export: export,
      repair: repair,
      install: install,
      shareRow: shareRow,
      actionRow: actionRow,
      column: column
    )
  }
}
