import AppKit
import Darwin
import Foundation
import NTFSMountCore
import Security
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

  /// Button copy: Install when the socket is missing; Update only if a live helper is stale.
  static var helperOfferIsUpdate: Bool {
    EnvironmentDiagnose.helperOfferIsUpdate(
      socketExists: daemonReady,
      helperNeedsUpdate: helperNeedsUpdate
    )
  }

  /// LSUIElement agents must become a regular app before osascript / SMAppService password UI.
  static func prepareForAdminPrompt() {
    let apply = {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    }
    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.sync(execute: apply)
    }
  }

  /// Ad-hoc LaunchDaemons cannot use SMAppService's BundleProgram; osascript installs a bash trampoline.
  private static var bundleIsAdHoc: Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
          let staticCode
    else { return true }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as NSDictionary?
    else { return true }
    if let flags = dict[kSecCodeInfoFlags] as? NSNumber {
      return flags.uint32Value & 0x0002 != 0 // kSecCodeSignatureAdhoc
    }
    let certs = dict[kSecCodeInfoCertificates] as? [Any]
    return certs == nil || certs?.isEmpty == true
  }

  /// SMAppService and osascript must both leave the same root-owned pins.
  private static var sealedHelperMatchesBundle: Bool {
    let fm = FileManager.default
    guard fm.isReadableFile(atPath: AppIdentity.helperSupportPath),
          fm.isReadableFile(atPath: AppIdentity.allowedCDHashPath),
          fm.isReadableFile(atPath: AppIdentity.helperStampPath),
          fm.isReadableFile(atPath: AppIdentity.appPathFile),
          let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil),
          let sha = AppIdentity.sha256File(bundled),
          let stamp = try? String(contentsOfFile: AppIdentity.helperStampPath, encoding: .utf8)
    else { return false }
    return stamp.contains(sha)
  }

  struct Outcome {
    let ok: Bool
    let text: String
  }

  static func installHelper() -> Outcome {
    prepareForAdminPrompt()
    guard let helper = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil)
    else {
      return Outcome(ok: false, text: L10n.t("privileged.missingHelper"))
    }
    let helperd = Bundle.main.bundlePath + "/Contents/MacOS/ntfsmount-helperd"
    guard FileManager.default.isExecutableFile(atPath: helperd) else {
      return Outcome(ok: false, text: L10n.t("privileged.missingDaemon"))
    }

    var smOk = false
    if !bundleIsAdHoc, registerDaemonService() {
      kickstartUntilSocket()
      if daemonReady && sealedHelperMatchesBundle { smOk = true }
    }

    if !smOk {
      try? SMAppService.daemon(plistName: "com.bioapple.ntfsmount.helper.plist").unregister()
      guard let installer = Bundle.main.path(forResource: "install-helper", ofType: "sh") else {
        return Outcome(ok: false, text: L10n.t("privileged.missingInstallScript"))
      }
      let fallback = copyToTempAndRun(
        ["bash"],
        files: [installer, helper, helperd],
        extra: [NSUserName(), Bundle.main.bundlePath]
      )
      if !fallback.ok { return fallback }
      kickstartUntilSocket()
      if hasLegacySudoers || FileManager.default.fileExists(atPath: AppIdentity.legacyHelperPath) {
        _ = removeLegacySudoers()
      }
      if !daemonReady {
        return Outcome(ok: false, text: failedInstallText(fallback.text))
      }
      return Outcome(
        ok: true,
        text: L10n.format("privileged.installedPassword", fallback.text)
      )
    }

    if hasLegacySudoers || FileManager.default.fileExists(atPath: AppIdentity.legacyHelperPath) {
      _ = removeLegacySudoers()
    }
    return Outcome(ok: true, text: L10n.t("privileged.installedSM"))
  }

  static func failedInstallText(_ helperOutput: String) -> String {
    var parts = [L10n.format("privileged.socketMissing", AppIdentity.helperSocket)]
    let trimmed = helperOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { parts.append(trimmed) }
    return parts.joined(separator: "\n\n")
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

  private static func kickstartUntilSocket(seconds: Double = 5) {
    let path = AppIdentity.helperSocket
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: path) { return }
      guard let launchctl = CommandPath.find("launchctl") else { return }
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: launchctl)
      proc.arguments = ["kickstart", "-k", "system/com.bioapple.ntfsmount.helper"]
      proc.standardOutput = Pipe()
      proc.standardError = Pipe()
      try? proc.run()
      proc.waitUntilExit()
      Thread.sleep(forTimeInterval: 0.1)
    }
  }

  /// Restart the LaunchDaemon after a repair. Does not change firewall rules.
  @discardableResult
  static func restartHelper() -> Outcome {
    guard systemHelperInstalled else {
      return Outcome(ok: false, text: L10n.t("privileged.notFound"))
    }
    kickstartUntilSocket()
    if daemonReady {
      return Outcome(ok: true, text: "ok helper-restarted")
    }
    return Outcome(ok: false, text: L10n.t("privileged.noResponse"))
  }

  private static func removeLegacySudoers() -> Outcome {
    guard let rm = CommandPath.find("rm") else {
      return Outcome(ok: false, text: L10n.t("privileged.commFailed"))
    }
    return runAdmin(parts: [
      rm, "-f",
      AppIdentity.legacySudoers,
      AppIdentity.legacyHelperPath,
    ])
  }

  static func uninstallHelper() -> Outcome {
    guard let script = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh") else {
      return Outcome(ok: false, text: L10n.t("privileged.missingUninstallScript"))
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

  private static let helperClientQueue = DispatchQueue(label: "com.bioapple.ntfsmount.helper-client")

  private static func runArgs(_ args: [String]) -> Outcome {
    if systemHelperInstalled && helperNeedsUpdate {
      return Outcome(ok: false, text: L10n.t("privileged.mismatch"))
    }
    if let via = runViaDaemon(args) {
      return via
    }
    return Outcome(ok: false, text: L10n.t("privileged.notFound"))
  }

  private static func runViaDaemon(_ args: [String]) -> Outcome? {
    helperClientQueue.sync { transactViaDaemon(args) }
  }

  private static func transactViaDaemon(_ args: [String]) -> Outcome? {
    guard let v2 = HelperIpc.encodeV2(args) else {
      return Outcome(ok: false, text: L10n.t("privileged.commFailed"))
    }
    guard let first = transactDaemonReconnect(v2, recvSec: HelperIpc.recvTimeoutSec(command: args.first ?? "")) else { return nil }
    if first.ok { return first }
    if first.text.contains("协议错误"), let v1 = HelperIpc.encodeV1Compat(args) {
      return transactDaemonReconnect(v1, recvSec: HelperIpc.recvTimeoutSec(command: args.first ?? "")) ?? first
    }
    return first
  }

  private static func transactDaemonReconnect(_ payload: Data, recvSec: Int) -> Outcome? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var timeout = timeval(tv_sec: recvSec, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
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
    return transactDaemon(fd: fd, payload: payload, wallSec: recvSec)
  }

  private static func transactDaemon(fd: Int32, payload: Data, wallSec: Int) -> Outcome? {
    let sent = payload.withUnsafeBytes { raw in
      send(fd, raw.baseAddress, raw.count, 0)
    }
    guard sent == payload.count else { return Outcome(ok: false, text: L10n.t("privileged.commFailed")) }
    shutdown(fd, SHUT_WR)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    let deadline = Date().addingTimeInterval(TimeInterval(wallSec))
    var peerClosed = false
    while Date() < deadline {
      let n = recv(fd, &buf, buf.count, 0)
      if n < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT {
          return Outcome(ok: false, text: L10n.t("privileged.timeout"))
        }
        break
      }
      if n == 0 {
        peerClosed = true
        break
      }
      out.append(buf, count: n)
      if HelperIpc.stripHeartbeats(out).count > 512 * 1024 { break }
    }
    let text = String(data: HelperIpc.stripHeartbeats(out), encoding: .utf8) ?? ""
    if text.hasPrefix("OK\n") {
      return Outcome(ok: true, text: String(text.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if text.hasPrefix("ERR\n") {
      return Outcome(ok: false, text: String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if !peerClosed {
      return Outcome(ok: false, text: L10n.t("privileged.timeout"))
    }
    if text.isEmpty {
      return Outcome(ok: false, text: L10n.t("privileged.noResponse"))
    }
    return Outcome(ok: false, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func runAdmin(parts: [String]) -> Outcome {
    prepareForAdminPrompt()
    if !Thread.isMainThread {
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard let osascript = CommandPath.find("osascript") else {
      return Outcome(ok: false, text: L10n.t("privileged.commFailed"))
    }
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
    osa.executableURL = URL(fileURLWithPath: osascript)
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
