import AppKit
import Foundation

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
    if !isArm64 { reasons.append("不支持 Intel Mac（x86_64）。需要 Apple Silicon（M 芯片）") }
    if !osOK { reasons.append("需要 macOS 13.0 或更高版本") }
    guard !reasons.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "无法运行 \(AppIdentity.productName)"
    alert.informativeText = reasons.joined(separator: "\n")
    alert.addButton(withTitle: "退出")
    alert.runModal()
    NSApp.terminate(nil)
  }
}

enum SigningStatus {
  static var isDeveloperID: Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
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
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
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
  static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/ntfsmount.log")
  }

  static func append(_ line: String) {
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
  }

  static func tail(_ maxLines: Int = 80) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return "还没有日志。挂载或格式化之后会出现在 \(url.path)"
    }
    let lines = text.split(whereSeparator: \.isNewline)
    return lines.suffix(maxLines).joined(separator: "\n")
  }
}
