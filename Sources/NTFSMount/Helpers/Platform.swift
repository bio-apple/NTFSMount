import AppKit
import Foundation
import NTFSMountCore
import os

enum PlatformGate {
  static var isArm64: Bool {
    #if arch(arm64)
    true
    #else
    false
    #endif
  }

  static var osOK: Bool {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13
  }

  @MainActor
  static func enforceOrTerminate() {
    var reasons: [String] = []
    if !isArm64 { reasons.append(L10n.t("platform.noIntel")) }
    if !osOK { reasons.append(L10n.t("platform.needOS")) }
    guard !reasons.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.format("platform.cannotRun", AppIdentity.productName)
    alert.informativeText = reasons.joined(separator: "\n")
    alert.addButton(withTitle: L10n.t("quit"))
    alert.runModal()
    NSApp.terminate(nil)
  }
}

enum SigningStatus {
  static var isDeveloperID: Bool {
    guard let codesign = CommandPath.find("codesign") else { return false }
    let result = capture(executable: codesign, arguments: ["-dv", "--verbose=4", Bundle.main.bundlePath])
    return result.stderr.contains("Developer ID Application")
  }

  static var isNotarized: Bool {
    guard let spctl = CommandPath.find("spctl") else { return false }
    let result = capture(
      executable: spctl,
      arguments: ["--assess", "--type", "execute", "-v", Bundle.main.bundlePath]
    )
    return result.status == 0 && result.stderr.lowercased().contains("notarized")
  }

  /// `Process.waitUntilExit` on the main thread runs the run loop. That re-enters SwiftUI
  /// and aborts (AttributeGraph precondition) when called from a view body.
  private static func capture(executable: String, arguments: [String]) -> (status: Int32, stderr: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    let err = Pipe()
    proc.standardOutput = Pipe()
    proc.standardError = err
    do {
      try proc.run()
    } catch {
      return (1, "")
    }
    let wait = { proc.waitUntilExit() }
    if Thread.isMainThread {
      DispatchQueue.global(qos: .userInitiated).sync(execute: wait)
    } else {
      wait()
    }
    let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (proc.terminationStatus, text)
  }
}

enum AppLog {
  static let app = Logger(subsystem: AppIdentity.bundleId, category: "app")
  static let helper = Logger(subsystem: AppIdentity.bundleId, category: "helper")
  static let volume = Logger(subsystem: AppIdentity.bundleId, category: "volume")
  static let diagnose = Logger(subsystem: AppIdentity.bundleId, category: "diagnose")

  static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/ntfsmount.log")
  }

  /// Session file log for in-app diagnose. Removed when the app quits.
  /// Unified Logging gets the same line as `.private` so paths stay redacted.
  static func append(_ line: String, unified: Bool = true) {
    let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    if let data = text.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
          defer { try? handle.close() }
          _ = try? handle.seekToEnd()
          try? handle.write(contentsOf: data)
        }
      } else {
        try? data.write(to: url)
      }
    }
    if unified {
      app.info("\(line, privacy: .private)")
    }
  }

  /// Drop the settings log. Does not touch system Console / unified logging.
  static func clear() {
    let fm = FileManager.default
    for path in [url.path, url.path + ".old", "/tmp/ntfsmount.log"] {
      try? fm.removeItem(atPath: path)
    }
  }

  static func tail(_ maxLines: Int = 80) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return L10n.format("log.empty", url.path)
    }
    let lines = text.split(whereSeparator: \.isNewline)
    return lines.suffix(maxLines).joined(separator: "\n")
  }
}
