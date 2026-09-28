import Darwin
import Foundation
import NTFSMountCore

/// Live, read-only probes. Never mounts, formats, or installs the helper.
enum EnvironmentDiagnoseRunner {
  static let helperSocket = "/var/run/com.bioapple.ntfsmount.sock"
  static let fuseTBin = "/Library/Application Support/fuse-t/bin"
  static let fuseTApp = "/Applications/FUSE-T.app"

  static func snapshot() -> DiagnoseSnapshot {
    if let fromScript = runBundledScript() {
      return fromScript
    }
    return liveSnapshot()
  }

  static func liveSnapshot() -> DiagnoseSnapshot {
    var snap = DiagnoseSnapshot()
    fillPlatform(&snap)
    fillRuntime(&snap)
    fillHelper(&snap)
    fillConflicts(&snap)
    fillGatekeeper(&snap)
    return snap
  }

  static func runBundledScript() -> DiagnoseSnapshot? {
    guard let script = bundledScriptPath() else { return nil }
    let cap = runCapture(
      "/bin/bash",
      [script, "--json"],
      timeout: 25
    )
    guard cap.status == 0, !cap.data.isEmpty else { return nil }
    return EnvironmentDiagnose.parseJSON(cap.data)
  }

  static func bundledScriptPath() -> String? {
    let fm = FileManager.default
    let candidates = [
      Bundle.main.path(forResource: "ntfsmount-diagnose", ofType: "sh"),
      Bundle.main.bundlePath + "/Contents/Resources/ntfsmount-diagnose.sh",
    ]
    return candidates.compactMap { $0 }.first { fm.isReadableFile(atPath: $0) }
  }

  // MARK: - platform / binaries

  static func fillPlatform(_ snap: inout DiagnoseSnapshot) {
    #if arch(arm64)
    snap.appleSilicon = true
    snap.arch = "arm64"
    #else
    snap.appleSilicon = false
    snap.arch = "x86_64"
    #endif
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    snap.macosMajor = ver.majorVersion
    snap.macosVersion = "\(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)"
    snap.macosProduct = "macOS"
    snap.pinnedFuseT = EnvironmentDiagnose.pinnedFuseT
  }

  static func fillRuntime(_ snap: inout DiagnoseSnapshot) {
    if let path = bundledTool("ntfs-3g") {
      snap.bundledNtfs3g = true
      snap.ntfs3gPath = path
      let parsed = probeNtfs3gAt(path)
      snap.ntfs3gVersion = parsed.displayVersion
      snap.ntfs3gRaw = parsed.raw
      snap.ntfs3gAllowed = parsed.isAllowed
    }
    snap.bundledNtfsfix = bundledTool("ntfsfix") != nil
    if let go = bundledTool("go-nfsv4") {
      snap.bundledGoNfsv4 = true
      snap.goNfsv4Path = go
    }
    snap.systemFuseTVersion = systemFuseTVersion()
  }

  /// 只执行捆绑路径，不用 PATH 里的 `ntfs-3g`。
  static func probeNtfs3g() -> Ntfs3gVersion.Parsed {
    guard let path = bundledTool("ntfs-3g") else {
      return Ntfs3gVersion.parse("")
    }
    return probeNtfs3gAt(path)
  }

  static func probeNtfs3gAt(_ path: String) -> Ntfs3gVersion.Parsed {
    var cap = runCapture(path, ["--version"], timeout: 3, combineErr: true)
    var text = String(data: cap.data, encoding: .utf8) ?? ""
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      cap = runCapture(path, ["-V"], timeout: 3, combineErr: true)
      text = String(data: cap.data, encoding: .utf8) ?? ""
    }
    return Ntfs3gVersion.parse(text)
  }

  static func bundledTool(_ name: String) -> String? {
    let fm = FileManager.default
    var paths = [
      Bundle.main.bundlePath + "/Contents/MacOS/" + name,
    ]
    if let exe = Bundle.main.executableURL {
      paths.append(exe.deletingLastPathComponent().appendingPathComponent(name).path)
    }
    return paths.first { fm.isExecutableFile(atPath: $0) }
  }

  static func systemFuseTVersion() -> String {
    let fm = FileManager.default
    if let named = try? fm.contentsOfDirectory(atPath: fuseTBin) {
      if let hit = named.first(where: { $0.hasPrefix("go-nfsv4-") }) {
        return String(hit.dropFirst("go-nfsv4-".count))
      }
    }
    let link = fuseTBin + "/go-nfsv4"
    if let dest = try? fm.destinationOfSymbolicLink(atPath: link), dest.hasPrefix("go-nfsv4-") {
      return String(dest.dropFirst("go-nfsv4-".count))
    }
    let plist = fuseTApp + "/Contents/Info.plist"
    if let dict = NSDictionary(contentsOfFile: plist) as? [String: Any],
       let ver = dict["CFBundleShortVersionString"] as? String {
      return ver
    }
    return ""
  }

  // MARK: - helper ping (socket only; never install)

  static func fillHelper(_ snap: inout DiagnoseSnapshot) {
    let exists = FileManager.default.fileExists(atPath: helperSocket)
    snap.helperSocketExists = exists
    snap.helperPing = exists ? pingHelper() : "absent"
  }

  static func pingHelper() -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return "connect_failed: socket" }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
        _ = strncpy(dst, helperSocket, 104)
      }
    }
    let cr = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard cr == 0 else { return "connect_failed: connect" }
    let payload = "v1 1\nversion\n"
    guard let data = payload.data(using: .utf8) else { return "connect_failed: encode" }
    let sent = data.withUnsafeBytes { raw in
      send(fd, raw.baseAddress, raw.count, 0)
    }
    guard sent == data.count else { return "connect_failed: send" }
    shutdown(fd, SHUT_WR)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while out.count < 8192 {
      let n = recv(fd, &buf, buf.count, 0)
      if n <= 0 { break }
      out.append(buf, count: n)
    }
    let text = String(data: out, encoding: .utf8) ?? ""
    let flat = text.replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if flat.contains("调用方未通过签名校验") { return "alive_caller_rejected" }
    if let range = flat.range(of: "HELPER_VERSION=") {
      return String(flat[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
    }
    if flat.isEmpty { return "connect_failed: empty" }
    return "response: \(flat)"
  }

  // MARK: - optional conflicts (never required)

  static func fillConflicts(_ snap: inout DiagnoseSnapshot) {
    snap.brewMacFuse = brewMacFuseStatus()
    snap.kextMacFuse = kextMacFuseStatus()
    snap.sysextMacFuse = sysextMacFuseStatus()
  }

  static func brewExecutable() -> String? {
    let fm = FileManager.default
    var dirs: [String] = []
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      dirs.append(contentsOf: path.split(separator: ":").map(String.init))
    }
    dirs.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])
    var seen = Set<String>()
    for dir in dirs {
      guard seen.insert(dir).inserted else { continue }
      let candidate = (dir as NSString).appendingPathComponent("brew")
      if fm.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }

  static func brewMacFuseStatus() -> String {
    guard let brew = Self.brewExecutable() else { return "brew_missing" }
    let cap = runCapture(brew, ["list", "macfuse"], timeout: 3)
    return cap.status == 0 ? "present" : "absent"
  }

  static func kextMacFuseStatus() -> String {
    guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/kextstat") else {
      return "unavailable"
    }
    let cap = runCapture("/usr/sbin/kextstat", [], timeout: 3)
    let text = (String(data: cap.data, encoding: .utf8) ?? "").lowercased()
    if text.contains("macfuse") || text.contains("osxfuse") { return "present" }
    return "absent"
  }

  static func sysextMacFuseStatus() -> String {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/systemextensionsctl") else {
      return "unavailable"
    }
    let cap = runCapture("/usr/bin/systemextensionsctl", ["list"], timeout: 5)
    let text = (String(data: cap.data, encoding: .utf8) ?? "").lowercased()
    if text.contains("macfuse") || text.contains("osxfuse") { return "present" }
    if text.isEmpty { return "unavailable" }
    return "absent"
  }

  // MARK: - gatekeeper

  static func fillGatekeeper(_ snap: inout DiagnoseSnapshot) {
    let app = Bundle.main.bundlePath
    snap.quarantine = hasQuarantine(app)
    snap.spctl = spctlStatus(app)
  }

  static func hasQuarantine(_ path: String) -> Bool {
    let cap = runCapture("/usr/bin/xattr", ["-p", "com.apple.quarantine", path], timeout: 2)
    let text = String(data: cap.data, encoding: .utf8) ?? ""
    return cap.status == 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static func spctlStatus(_ path: String) -> String {
    guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/spctl") else {
      return "unavailable"
    }
    let cap = runCapture(
      "/usr/sbin/spctl",
      ["--assess", "--type", "execute", "-v", path],
      timeout: 5,
      combineErr: true
    )
    let text = (String(data: cap.data, encoding: .utf8) ?? "").lowercased()
    if text.contains("notarized") { return "notarized" }
    if text.contains("rejected") { return "rejected" }
    if text.contains("accepted") { return "accepted" }
    return "unavailable"
  }

  struct Capture {
    var data: Data
    var status: Int32
  }

  static func runCapture(
    _ exe: String,
    _ args: [String],
    timeout: TimeInterval,
    combineErr: Bool = false
  ) -> Capture {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: exe)
    proc.arguments = args
    proc.environment = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": NSHomeDirectory(),
    ]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = combineErr ? out : Pipe()
    do {
      try proc.run()
    } catch {
      return Capture(data: Data(), status: -1)
    }
    let deadline = Date().addingTimeInterval(timeout)
    while proc.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if proc.isRunning {
      proc.terminate()
      proc.waitUntilExit()
      return Capture(data: Data(), status: -1)
    }
    return Capture(data: out.fileHandleForReading.readDataToEndOfFile(), status: proc.terminationStatus)
  }
}
