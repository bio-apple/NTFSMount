import AppKit
import DiskArbitration
import Foundation

enum AppIdentity {
  static let productName = "NTFS 读写"
  static let bundleId = "com.bioapple.ntfsmount"
  static let helperPath = "/usr/local/sbin/ntfs-rw-helper"
  static let helperVersion = "4"
  static let sourceURL = "https://github.com/bio-apple/NTFSMount"
  static let daemonPlist = "/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist"
  static let legacyDaemonPlist = "/Library/LaunchDaemons/local.ntfsmount.automount.plist"

  enum Defaults {
    static let autoMountUserOff = "com.bioapple.ntfsmount.autoMountUserOff"
    static let showDock = "com.bioapple.ntfsmount.showDock"
    static let didShowWindow = "com.bioapple.ntfsmount.didShowWindow"
    static let didShowCompat = "com.bioapple.ntfsmount.didShowCompatNotice"
    static let didMigrate = "com.bioapple.ntfsmount.didMigrateDefaults"
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

final class DiskWatch {
  private var session: DASession?
  private var pending: DispatchWorkItem?
  var onChange: (() -> Void)?

  func start() {
    guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
    self.session = session
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    DARegisterDiskAppearedCallback(session, nil, { _, ctx in
      guard let ctx else { return }
      Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
    }, ctx)
    DARegisterDiskDisappearedCallback(session, nil, { _, ctx in
      guard let ctx else { return }
      Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
    }, ctx)
    DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, ctx in
      guard let ctx else { return }
      Unmanaged<DiskWatch>.fromOpaque(ctx).takeUnretainedValue().schedule()
    }, ctx)
    DASessionSetDispatchQueue(session, DispatchQueue.main)
  }

  private func schedule() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.onChange?() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
  }
}

enum AppLog {
  static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/ntfsmount.log")
  }

  static func tail(_ maxLines: Int = 80) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return "还没有日志。挂载或格式化之后会出现在 \(url.path)"
    }
    let lines = text.split(whereSeparator: \.isNewline)
    return lines.suffix(maxLines).joined(separator: "\n")
  }
}
