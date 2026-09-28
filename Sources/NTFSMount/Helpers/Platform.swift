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
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: codesign)
    proc.arguments = ["-dv", "--verbose=4", Bundle.main.bundlePath]
    let err = Pipe()
    proc.standardOutput = Pipe()
    proc.standardError = err
    do {
      try proc.run()
      proc.waitUntilExit()
    } catch {
      return false
    }
    let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return text.contains("Developer ID Application")
  }

  static var isNotarized: Bool {
    guard let spctl = CommandPath.find("spctl") else { return false }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: spctl)
    proc.arguments = ["--assess", "--type", "execute", "-v", Bundle.main.bundlePath]
    let err = Pipe()
    proc.standardOutput = Pipe()
    proc.standardError = err
    try? proc.run()
    proc.waitUntilExit()
    let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return proc.terminationStatus == 0 && text.lowercased().contains("notarized")
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

  /// File log stays for in-app diagnose. Unified Logging gets the same line as `.private`
  /// so paths and helper output are redacted unless private data is enabled.
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

  static func tail(_ maxLines: Int = 80) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return L10n.format("log.empty", url.path)
    }
    let lines = text.split(whereSeparator: \.isNewline)
    return lines.suffix(maxLines).joined(separator: "\n")
  }
}
