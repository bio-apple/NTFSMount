import AppKit

/// MenuBarExtra `.help` is unreliable on the status item itself; pin `toolTip` on the button.
enum StatusItemTooltip {
  static func apply(_ text: String) {
    let value = text.isEmpty ? nil : text
    DispatchQueue.main.async {
      for window in NSApp.windows {
        let name = NSStringFromClass(type(of: window))
        guard name.contains("StatusBar") else { continue }
        if let button = firstButton(in: window.contentView) {
          button.toolTip = value
          return
        }
        window.contentView?.toolTip = value
      }
    }
  }

  private static func firstButton(in view: NSView?) -> NSStatusBarButton? {
    guard let view else { return nil }
    if let button = view as? NSStatusBarButton { return button }
    for sub in view.subviews {
      if let found = firstButton(in: sub) { return found }
    }
    return nil
  }
}
