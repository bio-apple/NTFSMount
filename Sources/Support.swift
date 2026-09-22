import AppKit
import CryptoKit
import DiskArbitration
import Foundation
import ServiceManagement

enum AppIdentity {
  static let productName = "NTFS 读写"
  static let bundleId = "com.bioapple.ntfsmount"
  static let helperVersion = "5"
  static let sourceURL = "https://github.com/bio-apple/NTFSMount"
  static let helperSocket = "/var/run/com.bioapple.ntfsmount.sock"
  static let helperDaemonPath = "/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
  static let helperSupportPath = "/Library/Application Support/NTFSMount/ntfs-rw-helper"
  static let helperStampPath = "/Library/Application Support/NTFSMount/helper.stamp"
  static let appPathFile = "/Library/Application Support/NTFSMount/app.path"
  static let legacyHelperPath = "/usr/local/sbin/ntfs-rw-helper"
  static let legacySudoers = "/etc/sudoers.d/ntfs-rw"
  static let daemonPlist = "/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist"
  static let helperDaemonPlist = "/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
  static let legacyDaemonPlist = "/Library/LaunchDaemons/local.ntfsmount.automount.plist"

  enum Defaults {
    static let autoMountUserOff = "com.bioapple.ntfsmount.autoMountUserOff"
    static let showDock = "com.bioapple.ntfsmount.showDock"
    static let didShowWindow = "com.bioapple.ntfsmount.didShowWindow"
    static let didShowCompat = "com.bioapple.ntfsmount.didShowCompatNotice"
    static let didMigrate = "com.bioapple.ntfsmount.didMigrateDefaults"
    static let didAcceptLegal = "com.bioapple.ntfsmount.didAcceptLegal"
    static let didAcceptWritable = "com.bioapple.ntfsmount.didAcceptWritable"
    static let didShowGatekeeper = "com.bioapple.ntfsmount.didShowGatekeeper"
    static let lastHelperSHA = "com.bioapple.ntfsmount.lastHelperSHA"
  }

  static func migrateDefaultsIfNeeded() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: Defaults.didMigrate) else { return }
    let map = [
      "local.ntfsmount.autoMountUserOff": Defaults.autoMountUserOff,
      "local.ntfsmount.didShowCompatNotice": Defaults.didShowCompat,
    ]
    for (old, new) in map where d.object(forKey: new) == nil && d.object(forKey: old) != nil {
      d.set(d.object(forKey: old), forKey: new)
    }
    d.set(true, forKey: Defaults.didMigrate)
  }

  static var writableStampURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/com.bioapple.ntfsmount/writable-accepted")
  }

  static func markWritableAccepted() {
    UserDefaults.standard.set(true, forKey: Defaults.didAcceptWritable)
    let url = writableStampURL
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "1\n".write(to: url, atomically: true, encoding: .utf8)
  }

  static func sha256File(_ path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

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
    if !isArm64 { reasons.append("需要 Apple Silicon（M 芯片）") }
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

enum UserFacingError {
  static func message(from raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "操作失败，请查看日志。" }
    let lower = t.lowercased()
    if lower.contains("user canceled") || t.contains("-128") || lower.contains("(-128)") {
      return "已取消。"
    }
    if lower.contains("no such file") || t.contains("(127)") || lower.contains("not found") {
      return "安装助手失败，请再试一次。详情已写入日志。"
    }
    if lower.contains("execution error") || lower.contains("osascript") || lower.contains("0:") {
      return "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。"
    }
    if lower.contains("password") && lower.contains("sudo") {
      return "挂载助手需要更新。请在窗口点「更新…」。"
    }
    if t.hasPrefix("error:") {
      return String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
    }
    AppLog.append("raw: \(t)")
    if t.count > 180 {
      return "操作失败。详情已写入 \(AppLog.url.path)"
    }
    return t
  }
}

enum LegalGate {
  @MainActor
  static func confirmOrTerminate() {
    let d = UserDefaults.standard
    if !d.bool(forKey: AppIdentity.Defaults.didShowGatekeeper), !SigningStatus.isNotarized {
      d.set(true, forKey: AppIdentity.Defaults.didShowGatekeeper)
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.alertStyle = .informational
      alert.messageText = "当前构建未公证"
      alert.informativeText = """
      正式分发需要 Developer ID 公证，否则系统会提示无法验证开发者。

      若已被拦截：按住 Control 点应用 → 打开。
      自己用可以继续；发给别人请先公证。说明见应用包内 LICENSE 与文档。
      """
      alert.addButton(withTitle: "继续")
      alert.runModal()
    }

    guard !d.bool(forKey: AppIdentity.Defaults.didAcceptLegal) else { return }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "使用前请确认"
    alert.informativeText = """
    1. 以可写方式挂载或格式化 NTFS 可能损坏数据。请先备份。
    2. 捆绑的 FUSE-T go-nfsv4 仅供个人使用。作为产品分发或销售前，须向 FUSE-T 取得许可（https://www.fuse-t.org/）。
    3. 本应用不联网、不收集账户。日志只写在本机。

    不同意请退出。
    """
    alert.addButton(withTitle: "同意并继续")
    alert.addButton(withTitle: "退出")
    if alert.runModal() != .alertFirstButtonReturn {
      NSApp.terminate(nil)
      return
    }
    d.set(true, forKey: AppIdentity.Defaults.didAcceptLegal)
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
    guard alert.runModal() == .alertSecondButtonReturn else { return false }
    AppIdentity.markWritableAccepted()
    return true
  }
}

final class DiskWatch {
  private var session: DASession?
  private var pending: DispatchWorkItem?
  var onChange: (() -> Void)?

  func start() {
    guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
    self.session = session
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    DARegisterDiskAppearedCallback(session, nil, diskWatchAppeared, ctx)
    DARegisterDiskDisappearedCallback(session, nil, diskWatchDisappeared, ctx)
    DARegisterDiskDescriptionChangedCallback(session, nil, nil, diskWatchChanged, ctx)
    DASessionSetDispatchQueue(session, DispatchQueue.main)
  }

  func stop() {
    pending?.cancel()
    pending = nil
    guard let session else { return }
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    DAUnregisterCallback(session, unsafeBitCast(diskWatchAppeared, to: UnsafeMutableRawPointer.self), ctx)
    DAUnregisterCallback(session, unsafeBitCast(diskWatchDisappeared, to: UnsafeMutableRawPointer.self), ctx)
    DAUnregisterCallback(session, unsafeBitCast(diskWatchChanged, to: UnsafeMutableRawPointer.self), ctx)
    DASessionSetDispatchQueue(session, nil)
    self.session = nil
  }

  deinit { stop() }

  fileprivate func schedule() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.onChange?() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }
}

private func diskWatchAppeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
}

private func diskWatchDisappeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
}

private func diskWatchChanged(_ disk: DADisk, _ keys: CFArray, _ ctx: UnsafeMutableRawPointer?) {
  guard let ctx else { return }
  Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
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
