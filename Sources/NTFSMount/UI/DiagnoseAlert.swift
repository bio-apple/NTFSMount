import AppKit
import NTFSMountCore

/// Scrollable diagnose window. Copy / close; never install helper.
enum EnvironmentDiagnosePresenter {
  @MainActor
  static func present() {
    DiagnoseWindowController.shared.show()
  }
}

@MainActor
final class DiagnoseWindowController: NSObject, NSWindowDelegate {
  static let shared = DiagnoseWindowController()

  private var window: NSWindow?
  private var textView: NSTextView?
  private var spinner: NSProgressIndicator?
  private var copyButton: NSButton?
  private var running = false
  private var report = ""
  private var generation = 0

  func show() {
    if window == nil {
      buildWindow()
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    if !running {
      start()
    }
  }

  func windowWillClose(_ notification: Notification) {
    running = false
  }

  private func start() {
    generation += 1
    let token = generation
    running = true
    report = ""
    setBody(L10n.t("diagnose.checking"))
    spinner?.startAnimation(nil)
    spinner?.isHidden = false
    copyButton?.isEnabled = false
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let snap = EnvironmentDiagnoseRunner.snapshot()
      let lines = EnvironmentDiagnose.lines(from: snap)
      let text = EnvironmentDiagnose.reportText(from: lines)
      AppLog.append("diagnose\n\(text)")
      DispatchQueue.main.async {
        guard let self, self.generation == token else { return }
        self.running = false
        self.report = text
        self.setBody(text)
        self.spinner?.stopAnimation(nil)
        self.spinner?.isHidden = true
        self.copyButton?.isEnabled = true
      }
    }
  }

  private func setBody(_ text: String) {
    textView?.string = text
  }

  @objc private func copyReport() {
    let text = report.isEmpty ? (textView?.string ?? "") : report
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  @objc private func closeWindow() {
    window?.close()
  }

  private func buildWindow() {
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    win.title = L10n.t("diagnose.alertTitle")
    win.minSize = NSSize(width: 420, height: 280)
    win.isReleasedWhenClosed = false
    win.delegate = self
    win.center()

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))

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

    let copy = NSButton(title: L10n.t("diagnose.copy"), target: self, action: #selector(copyReport))
    copy.bezelStyle = .rounded
    copy.translatesAutoresizingMaskIntoConstraints = false
    copy.isEnabled = false

    let close = NSButton(title: L10n.t("ok.gotIt"), target: self, action: #selector(closeWindow))
    close.bezelStyle = .rounded
    close.keyEquivalent = "\r"
    close.translatesAutoresizingMaskIntoConstraints = false

    content.addSubview(spinner)
    content.addSubview(scroll)
    content.addSubview(copy)
    content.addSubview(close)

    NSLayoutConstraint.activate([
      spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      spinner.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      scroll.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 10),
      scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -12),
      copy.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
      copy.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -12),
      close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      close.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
    ])

    win.contentView = content
    self.window = win
    self.textView = text
    self.spinner = spinner
    self.copyButton = copy
  }
}
