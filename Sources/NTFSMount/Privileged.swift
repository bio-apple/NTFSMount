import Darwin
import Foundation
import NTFSMountCore
import ServiceManagement

/// 持续提权走 SMAppService + LaunchDaemon（Cocoa 原生平权）。
/// osascript「do shell script … with administrator privileges」仅用于一次性安装/卸载。
/// 不引入 AuthorizationServices 平行 API，也不写 sudoers NOPASSWD。
enum Privileged {
  static var systemHelperInstalled: Bool {
    FileManager.default.fileExists(atPath: AppIdentity.helperDaemonPath)
      || FileManager.default.fileExists(atPath: AppIdentity.helperDaemonPlist)
      || FileManager.default.fileExists(atPath: AppIdentity.helperSocket)
      || FileManager.default.fileExists(atPath: AppIdentity.legacySudoers)
      || SMAppService.daemon(plistName: "com.bioapple.ntfsmount.helper.plist").status == .enabled
  }

  static var autoMountEnabled: Bool {
    FileManager.default.fileExists(atPath: AppIdentity.daemonPlist)
      || FileManager.default.fileExists(atPath: AppIdentity.legacyDaemonPlist)
  }

  static var hasLegacySudoers: Bool {
    FileManager.default.fileExists(atPath: AppIdentity.legacySudoers)
  }

  static var helperNeedsUpdate: Bool {
    if hasLegacySudoers { return true }
    guard systemHelperInstalled else { return false }
    guard let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil),
          let sha = AppIdentity.sha256File(bundled)
    else { return true }
    if UserDefaults.standard.string(forKey: AppIdentity.Defaults.lastHelperSHA) != sha {
      if let stamp = try? String(contentsOfFile: AppIdentity.helperStampPath, encoding: .utf8),
         stamp.contains(sha) {
        UserDefaults.standard.set(sha, forKey: AppIdentity.Defaults.lastHelperSHA)
        return hasLegacySudoers
      }
      return true
    }
    return !daemonReady
  }

  static var daemonReady: Bool {
    FileManager.default.fileExists(atPath: AppIdentity.helperSocket)
  }

  struct Outcome {
    let ok: Bool
    let text: String
  }

  static func installHelper() -> Outcome {
    guard let helper = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil)
    else {
      return Outcome(ok: false, text: "应用包内缺少挂载助手，请重新安装。")
    }
    let helperd = Bundle.main.bundlePath + "/Contents/MacOS/ntfsmount-helperd"
    guard FileManager.default.isExecutableFile(atPath: helperd) else {
      return Outcome(ok: false, text: "应用包内缺少特权守护进程，请重新安装。")
    }

    if registerDaemonService() {
      if hasLegacySudoers || FileManager.default.fileExists(atPath: AppIdentity.legacyHelperPath) {
        _ = removeLegacySudoers()
      }
      return Outcome(ok: true, text: "已用系统服务注册挂载助手。")
    }

    guard let installer = Bundle.main.path(forResource: "install-helper", ofType: "sh") else {
      return Outcome(ok: false, text: "应用包内缺少安装脚本，请重新安装。")
    }
    let fallback = copyToTempAndRun(
      ["bash"],
      files: [installer, helper, helperd],
      extra: [NSUserName(), Bundle.main.bundlePath]
    )
    if fallback.ok {
      return Outcome(
        ok: true,
        text: "已用管理员密码安装 LaunchDaemon（未公证包通常走这条路径）。\(fallback.text)"
      )
    }
    return fallback
  }

  private static func registerDaemonService() -> Bool {
    let service = SMAppService.daemon(plistName: "com.bioapple.ntfsmount.helper.plist")
    if service.status == .enabled { return true }
    do {
      try service.register()
    } catch {
      return false
    }
    return service.status == .enabled
  }

  private static func removeLegacySudoers() -> Outcome {
    runAdmin(parts: [
      "/bin/rm", "-f",
      AppIdentity.legacySudoers,
      AppIdentity.legacyHelperPath,
    ])
  }

  static func uninstallHelper() -> Outcome {
    guard let script = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh") else {
      return Outcome(ok: false, text: "应用包内缺少卸载脚本。")
    }
    try? SMAppService.daemon(plistName: "com.bioapple.ntfsmount.helper.plist").unregister()
    return copyToTempAndRun(["bash"], files: [script], extra: [])
  }

  private static func copyToTempAndRun(_ prefix: [String], files: [String], extra: [String]) -> Outcome {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfsmount-helper-install-\(ProcessInfo.processInfo.globallyUniqueString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: dir) }
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
      var copied: [String] = []
      for src in files {
        let dest = dir.appendingPathComponent((src as NSString).lastPathComponent)
        try fm.copyItem(atPath: src, toPath: dest.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        copied.append(dest.path)
      }
      return runAdmin(parts: prefix + copied + extra)
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }
  }

  static func run(_ cmd: String, extra: [String] = []) -> Outcome {
    runArgs([cmd] + extra)
  }

  static func run(_ cmd: String, _ deviceId: String, extra: [String] = []) -> Outcome {
    runArgs([cmd, deviceId] + extra)
  }

  private static func runArgs(_ args: [String]) -> Outcome {
    if systemHelperInstalled && helperNeedsUpdate {
      return Outcome(ok: false, text: "挂载助手与本应用不匹配，已拒绝运行。请先点「更新挂载助手」。")
    }
    if let via = runViaDaemon(args) {
      return via
    }
    return Outcome(ok: false, text: "未找到挂载助手。请点「安装挂载助手」。")
  }

  private static func runViaDaemon(_ args: [String]) -> Outcome? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = AppIdentity.helperSocket
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
        _ = strncpy(dst, path, 104)
      }
    }
    let cr = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard cr == 0 else { return nil }
    var payload = "v1 \(args.count)\n"
    for a in args { payload += a.replacingOccurrences(of: "\n", with: " ") + "\n" }
    guard let data = payload.data(using: .utf8) else { return nil }
    let sent = data.withUnsafeBytes { raw in
      send(fd, raw.baseAddress, raw.count, 0)
    }
    guard sent == data.count else { return Outcome(ok: false, text: "与挂载助手通信失败。") }
    shutdown(fd, SHUT_WR)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = recv(fd, &buf, buf.count, 0)
      if n <= 0 { break }
      out.append(buf, count: n)
      if out.count > 512 * 1024 { break }
    }
    let text = String(data: out, encoding: .utf8) ?? ""
    if text.hasPrefix("OK\n") {
      return Outcome(ok: true, text: String(text.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if text.hasPrefix("ERR\n") {
      return Outcome(ok: false, text: String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if text.isEmpty {
      return Outcome(ok: false, text: "挂载助手没有响应。请先安装或更新助手。")
    }
    return Outcome(ok: false, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func runAdmin(parts: [String]) -> Outcome {
    let source = """
    on run argv
      set cmd to ""
      repeat with a in argv
        set cmd to cmd & quoted form of (contents of a) & space
      end repeat
      do shell script cmd with administrator privileges
    end run
    """
    let osa = Process()
    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osa.arguments = ["-"] + parts
    let stdin = Pipe()
    let osaOut = Pipe()
    let osaErr = Pipe()
    osa.standardInput = stdin
    osa.standardOutput = osaOut
    osa.standardError = osaErr
    do {
      try osa.run()
      stdin.fileHandleForWriting.write(Data(source.utf8))
      stdin.fileHandleForWriting.closeFile()
      osa.waitUntilExit()
      let out = String(data: osaOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let err = String(data: osaErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if osa.terminationStatus == 0 {
        return Outcome(ok: true, text: out.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }
  }
}
