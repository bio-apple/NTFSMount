import AppKit
import Foundation
import NTFSMountCore
import Security
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
  private struct Facts {
    var developerID = false
    var notarized = false
  }

  private static let facts = load()

  static var isDeveloperID: Bool { facts.developerID }
  static var isNotarized: Bool { facts.notarized }

  /// Read the signature in-process. Spawning codesign/spctl and waiting on the main
  /// thread runs the run loop, re-enters SwiftUI, and aborts the settings window.
  private static func load() -> Facts {
    var staticCode: SecStaticCode?
    let created = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
    guard created == errSecSuccess, let staticCode else { return Facts() }
    var info: CFDictionary?
    let copyFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
    let copied = SecCodeCopySigningInformation(staticCode, copyFlags, &info)
    guard copied == errSecSuccess, let dict = info as NSDictionary? else { return Facts() }

    let flagValue = (dict[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
    let adHoc = flagValue & 0x0002 != 0
    var facts = Facts()
    if !adHoc, let certs = dict[kSecCodeInfoCertificates] as? [SecCertificate], let leaf = certs.first {
      var commonName: CFString?
      if SecCertificateCopyCommonName(leaf, &commonName) == errSecSuccess, let name = commonName as String? {
        facts.developerID = name.contains("Developer ID Application")
      }
    }
    facts.notarized = facts.developerID && dict[kSecCodeInfoStapledNotarizationTicket] != nil
    return facts
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
