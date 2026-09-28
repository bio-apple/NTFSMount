import AppKit
import NTFSMountCore

/// Scrollable diagnose window. Scan is read-only (never installs). After the report,
/// the user can choose to install the mount helper via the same `installHelper()` flow.
enum EnvironmentDiagnosePresenter {
  @MainActor
  static func present(store: VolumeStore) {
    DiagnoseWindowController.shared.show(store: store)
  }
}

@MainActor
final class DiagnoseWindowController: NSObject, NSWindowDelegate {
  static let shared = DiagnoseWindowController()

  private var window: NSWindow?
  private var textView: NSTextView?
  private var spinner: NSProgressIndicator?
  private var copyButton: NSButton?
  private var installButton: NSButton?
  private var hintField: NSTextField?
  private var hintCollapse: NSLayoutConstraint?
  private var buttonRow: NSStackView?
  private weak var store: VolumeStore?
  private var running = false
  private var installing = false
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
    if !running && !installing {
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
    report = ""
    setBody(L10n.t("diagnose.checking"))
    spinner?.startAnimation(nil)
    spinner?.isHidden = false
    copyButton?.isEnabled = false
    setHint(nil)
    setInstallVisible(false)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let snap = EnvironmentDiagnoseRunner.snapshot()
      let lines = EnvironmentDiagnose.lines(from: snap)
      let text = EnvironmentDiagnose.reportText(from: lines)
      AppLog.append("diagnose\n\(text)")
      DispatchQueue.main.async {
        guard let self, self.generation == token else { return }
        self.running = false
        self.report = text
        self.lastSnap = snap
        self.setBody(text)
        self.spinner?.stopAnimation(nil)
        self.spinner?.isHidden = true
        self.copyButton?.isEnabled = true
        self.updateActions(snap)
      }
    }
  }

  private func updateActions(_ snap: DiagnoseSnapshot) {
    if EnvironmentDiagnose.bundledComponentsBroken(snap) {
      setHint(L10n.t("diagnose.brokenBundle"))
    } else {
      setHint(nil)
    }

    let helperOffer = EnvironmentDiagnose.helperNeedsInstall(snap)
      || Privileged.helperNeedsUpdate
    setInstallVisible(helperOffer)
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
    store.installHelper { [weak self] outcome in
      guard let self else { return }
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

  private func showInstallFailure(_ detail: String) {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let logs = AppLog.tail(40)
    var block = "\n\n—— \(L10n.t("diagnose.installFailed")) ——\n"
    if !trimmed.isEmpty {
      block += trimmed + "\n"
    }
    block += "\n\(AppLog.url.path)\n\(logs)"
    let body = report.isEmpty ? block.trimmingCharacters(in: .whitespacesAndNewlines) : report + block
    report = body
    setBody(body)
    copyButton?.isEnabled = true
    let hint = trimmed.split(whereSeparator: \.isNewline).first.map(String.init)
    setHint(hint)
  }

  @objc private func closeWindow() {
    window?.close()
  }

  private func buildWindow() {
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    win.title = L10n.t("diagnose.alertTitle")
    win.minSize = NSSize(width: 420, height: 300)
    win.isReleasedWhenClosed = false
    win.delegate = self
    win.center()

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 440))

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
    hint.preferredMaxLayoutWidth = 520
    hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let copy = NSButton(title: L10n.t("diagnose.copy"), target: self, action: #selector(copyReport))
    copy.bezelStyle = .rounded
    copy.isEnabled = false

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

    let row = NSStackView(views: [copy, install, spacer, close])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false
    row.setVisibilityPriority(.notVisible, for: install)

    content.addSubview(spinner)
    content.addSubview(scroll)
    content.addSubview(hint)
    content.addSubview(row)

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
      hint.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -12),
      row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
    ])

    win.contentView = content
    self.window = win
    self.textView = text
    self.spinner = spinner
    self.copyButton = copy
    self.installButton = install
    self.hintField = hint
    self.hintCollapse = hintCollapse
    self.buttonRow = row
  }
}
