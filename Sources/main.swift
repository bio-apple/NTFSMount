import AppKit
import ServiceManagement
import SwiftUI

enum MacOSCompat {
  static let version = ProcessInfo.processInfo.operatingSystemVersion
  static var major: Int { version.majorVersion }
  static var isBelowMinimum: Bool { major < 13 }

  static var menuCaption: String {
    if isBelowMinimum {
      return "系统低于 macOS 13，未测试（最低 13.0）"
    }
    return "用户态 FUSE，不用内核扩展（macOS 13+ 已限制 kext）"
  }

  static var noticeTitle: String {
    isBelowMinimum ? "系统版本过低" : "兼容性说明"
  }

  static var noticeBody: String {
    if isBelowMinimum {
      return "本应用面向 macOS 13 Ventura 及更高版本构建。当前系统未测试，挂载可能失败。"
    }
    return "本应用不使用内核扩展。macOS 13 Ventura 起对 kext 限制更严，因此使用用户态 FUSE（ntfs-3g + FUSE-T）。若提示 FSKit/模块未启用，可忽略——助手已优先使用 NFS/用户态路径，请勿安装内核扩展。"
  }

  static func looksLikeKextOrFSKitBlock(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("fskit")
      || t.contains("kext")
      || t.contains("kernel extension")
      || t.contains("module is disabled")
      || t.contains("system extension")
      || text.contains("内核扩展")
  }

  private static let noticeKey = "local.ntfsmount.didShowCompatNotice"

  static var shouldShowLaunchNotice: Bool {
    !UserDefaults.standard.bool(forKey: noticeKey)
  }

  static func markLaunchNoticeShown() {
    UserDefaults.standard.set(true, forKey: noticeKey)
  }
}

@main
struct NTFSMountApp: App {
  @StateObject private var store = VolumeStore()

  var body: some Scene {
    MenuBarExtra {
      MenuRoot(store: store)
    } label: {
      Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
    }
    .menuBarExtraStyle(.menu)
  }
}

@MainActor
final class VolumeStore: ObservableObject {
  @Published var volumes: [NTFSVolume] = []
  @Published var message: String = ""
  @Published var busyId: String?
  @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
  @Published var helperInstalled: Bool = Privileged.systemHelperInstalled
  @Published var formatDisks: [FormatDisk] = []
  @Published var autoMount: Bool = Privileged.autoMountEnabled

  private var timer: Timer?

  var writableCount: Int { volumes.filter(\.isWritableFuse).count }
  var menuBarTitle: String {
    if volumes.isEmpty { return "NTFS" }
    if writableCount > 0 { return "NTFS \(writableCount)" }
    return "NTFS"
  }

  var menuBarSymbol: String {
    if writableCount > 0 { return "externaldrive.fill.badge.checkmark" }
    if volumes.contains(where: { !$0.mountPoint.isEmpty }) { return "externaldrive.fill.badge.questionmark" }
    if !volumes.isEmpty { return "externaldrive" }
    return "externaldrive.badge.questionmark"
  }

  init() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    DispatchQueue.main.async { [weak self] in
      self?.offerHelperInstallIfNeeded()
      self?.offerCompatNoticeIfNeeded()
    }
  }

  func offerHelperInstallIfNeeded() {
    if !helperInstalled {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "安装挂载助手"
      alert.informativeText = "第一次使用需要输入一次管理员密码。装好后，挂载硬盘就不用再输密码。"
      alert.addButton(withTitle: "安装")
      alert.addButton(withTitle: "稍后")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      installHelper()
      return
    }
    guard Privileged.helperNeedsUpdate else { return }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "更新挂载助手"
    alert.informativeText = "需要更新才能使用格式化、插入时自动挂载等新功能。将请求一次管理员密码。"
    alert.addButton(withTitle: "更新")
    alert.addButton(withTitle: "稍后")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    installHelper()
  }

  func offerCompatNoticeIfNeeded() {
    guard MacOSCompat.shouldShowLaunchNotice else { return }
    MacOSCompat.markLaunchNoticeShown()
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = MacOSCompat.isBelowMinimum ? .warning : .informational
    alert.messageText = MacOSCompat.noticeTitle
    alert.informativeText = MacOSCompat.noticeBody
    alert.addButton(withTitle: "知道了")
    alert.runModal()
  }

  func alertKextIgnored(_ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "挂载失败"
    alert.informativeText = """
    FSKit/内核扩展不可用是 macOS 13+ 的预期情况，可忽略。本应用不使用内核扩展，助手已优先使用 NFS/用户态 FUSE。请勿安装 kext。

    \(detail)
    """
    alert.addButton(withTitle: "知道了")
    alert.runModal()
  }

  func installHelper() {
    let result = Privileged.installHelper()
    helperInstalled = Privileged.systemHelperInstalled
    message = result.text
  }

  func showMainWindow() {
    MainWindowController.shared.show(store: self)
  }

  func refresh() {
    volumes = NTFSVolume.scan()
    formatDisks = FormatDisk.scan()
    autoMount = Privileged.autoMountEnabled
    helperInstalled = Privileged.systemHelperInstalled
  }

  func mount(_ vol: NTFSVolume) {
    run("mount", vol)
  }

  func unmount(_ vol: NTFSVolume) {
    run("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) {
    run("eject", vol)
  }

  func mountAll() {
    for vol in volumes where !vol.isWritableFuse {
      run("mount", vol)
    }
  }

  func confirmFormat(_ disk: FormatDisk) {
    NSApp.activate(ignoringOtherApps: true)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = disk.suggestedLabel
    field.placeholderString = "卷名"
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "抹掉「\(disk.name)」并格式化为 NTFS？"
    alert.informativeText = "\(disk.sizeLabel) · \(disk.id) · \(disk.fsHint)\n将删除盘上全部文件，且无法恢复。"
    alert.accessoryView = field
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "抹掉并格式化")
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    format(disk, label: sanitizeLabel(field.stringValue))
  }

  func format(_ disk: FormatDisk, label: String) {
    busyId = disk.id
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run("format", disk.id, extra: [label])
      DispatchQueue.main.async {
        self.busyId = nil
        self.message = result.text
        self.refresh()
        if result.ok, let vol = self.volumes.first(where: { wholeDiskId($0.id) == disk.id }) {
          self.mount(vol)
        }
      }
    }
  }

  func toggleLogin() {
    do {
      if launchAtLogin {
        try SMAppService.mainApp.unregister()
        launchAtLogin = false
      } else {
        try SMAppService.mainApp.register()
        launchAtLogin = true
      }
    } catch {
      message = "开机启动失败：\(error.localizedDescription)"
    }
  }

  func toggleAutoMount() {
    let cmd = autoMount ? "disable-automount" : "enable-automount"
    busyId = "automount"
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd)
      DispatchQueue.main.async {
        self.busyId = nil
        self.autoMount = Privileged.autoMountEnabled
        self.message = result.ok
          ? (self.autoMount ? "已打开插入时自动挂载" : "已关闭插入时自动挂载")
          : result.text
      }
    }
  }

  private func run(_ cmd: String, _ vol: NTFSVolume) {
    busyId = vol.id
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd, vol.id)
      DispatchQueue.main.async {
        self.busyId = nil
        if result.ok {
          self.message = result.text
          self.refresh()
          if cmd == "mount" {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
        } else {
          self.message = result.text
          self.refresh()
          if cmd == "mount", MacOSCompat.looksLikeKextOrFSKitBlock(result.text) {
            self.alertKextIgnored(result.text)
          }
        }
      }
    }
  }
}

func wholeDiskId(_ id: String) -> String {
  if let range = id.range(of: #"s\d"#, options: .regularExpression) {
    return String(id[..<range.lowerBound])
  }
  return id
}

private func sanitizeLabel(_ raw: String) -> String {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let cleaned = trimmed
    .replacingOccurrences(of: "/", with: "")
    .replacingOccurrences(of: "\"", with: "")
    .replacingOccurrences(of: "\\", with: "")
  let limited = String(cleaned.prefix(32))
  return limited.isEmpty ? "NTFS" : limited
}

struct NTFSVolume: Identifiable, Equatable {
  let id: String
  let name: String
  let size: Int64
  let mountPoint: String
  let isWritableFuse: Bool
  let isReadOnlyMounted: Bool
  let mediaName: String
  let usedBytes: Int64
  let freeBytes: Int64

  var expectedMountPoint: String { mountPoint.isEmpty ? "/Volumes/\(name)" : mountPoint }

  var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  var stateLabel: String {
    if isWritableFuse { return "可写" }
    if isReadOnlyMounted { return "系统只读" }
    return "未挂载"
  }

  var hasUsage: Bool {
    !mountPoint.isEmpty && (usedBytes + freeBytes) > 0
  }

  var usageRatio: Double {
    let total = usedBytes + freeBytes
    guard total > 0 else { return 0 }
    return min(1, Double(usedBytes) / Double(total))
  }

  static func scan() -> [NTFSVolume] {
    guard let list = diskutilPlist(["list", "-plist"]) else { return [] }
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var ids: [String] = []
    for disk in disks {
      for part in disk["Partitions"] as? [[String: Any]] ?? [] {
        if let ident = part["DeviceIdentifier"] as? String {
          ids.append(ident)
        }
      }
      if let ident = disk["DeviceIdentifier"] as? String,
         disk["Partitions"] == nil {
        ids.append(ident)
      }
    }

    let mountTable = currentMounts()

    var out: [NTFSVolume] = []
    for ident in ids {
      guard let info = diskutilPlist(["info", "-plist", ident]) else { continue }
      let fs = info["FilesystemName"] as? String ?? ""
      guard fs == "NTFS" else { continue }
      let name = info["VolumeName"] as? String
      let volumeName = (name?.isEmpty == false) ? name! : "NTFS-\(ident)"
      let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? 0
      let diskutilMp = info["MountPoint"] as? String ?? ""
      let expected = "/Volumes/\(volumeName)"
      let fuseMp = mountTable.fusePoints.contains(diskutilMp) ? diskutilMp
        : (mountTable.fusePoints.contains(expected) ? expected : "")
      let mp = fuseMp.isEmpty ? diskutilMp : fuseMp
      let fuse = !fuseMp.isEmpty
      let media = volumeMediaName(info: info, volumeName: volumeName)
      let diskutilFree = (info["VolumeFreeSpace"] as? NSNumber)?.int64Value
        ?? (info["FreeSpace"] as? NSNumber)?.int64Value
        ?? 0
      var used: Int64 = 0
      var free: Int64 = diskutilFree
      if !mp.isEmpty, let usage = fileSystemUsage(at: mp) {
        free = usage.free
        used = max(0, usage.total - usage.free)
      } else if size > 0, diskutilFree > 0 {
        used = max(0, size - diskutilFree)
      }
      out.append(
        NTFSVolume(
          id: ident,
          name: volumeName,
          size: size,
          mountPoint: mp,
          isWritableFuse: fuse,
          isReadOnlyMounted: !mp.isEmpty && !fuse,
          mediaName: media,
          usedBytes: used,
          freeBytes: free
        )
      )
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

private func volumeMediaName(info: [String: Any], volumeName: String) -> String {
  let media = info["MediaName"] as? String ?? ""
  if !media.isEmpty, media != volumeName { return media }
  let proto = info["BusProtocol"] as? String ?? ""
  if !proto.isEmpty { return proto }
  return ""
}

private func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? {
  guard let vals = try? FileManager.default.attributesOfFileSystem(forPath: path),
        let total = vals[.systemSize] as? NSNumber,
        let free = vals[.systemFreeSize] as? NSNumber
  else { return nil }
  return (total.int64Value, free.int64Value)
}

struct FormatDisk: Identifiable, Equatable {
  let id: String
  let name: String
  let size: Int64
  let fsHint: String

  var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  var suggestedLabel: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == id { return "NTFS" }
    return String(trimmed.prefix(32))
  }

  static func scan() -> [FormatDisk] {
    guard let list = diskutilPlist(["list", "-plist"]) else { return [] }
    let protected = protectedDisks()
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var out: [FormatDisk] = []
    for disk in disks {
      guard let ident = disk["DeviceIdentifier"] as? String,
            ident.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil
      else { continue }
      guard let info = diskutilPlist(["info", "-plist", ident]) else { continue }
      if info["Internal"] as? Bool == true { continue }
      let proto = info["BusProtocol"] as? String ?? ""
      if proto == "Disk Image" || proto == "Apple Fabric" { continue }
      if info["VirtualOrPhysical"] as? String == "Virtual" { continue }
      if protected.contains(ident) { continue }
      let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? 0
      guard size > 0 else { continue }
      let media = info["MediaName"] as? String ?? ""
      let parts = disk["Partitions"] as? [[String: Any]] ?? []
      var hint = "未格式化"
      var volName = ""
      for part in parts {
        let content = part["Content"] as? String ?? ""
        if content.uppercased().contains("EFI") { continue }
        if let pid = part["DeviceIdentifier"] as? String,
           let pinfo = diskutilPlist(["info", "-plist", pid]) {
          let fs = pinfo["FilesystemName"] as? String ?? ""
          hint = fs.isEmpty ? (content.isEmpty ? hint : content) : fs
          volName = pinfo["VolumeName"] as? String ?? ""
        } else if !content.isEmpty {
          hint = content
        }
        break
      }
      let name: String
      if !volName.isEmpty {
        name = volName
      } else if !media.isEmpty {
        name = media
      } else {
        name = ident
      }
      out.append(FormatDisk(id: ident, name: name, size: size, fsHint: hint))
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func protectedDisks() -> Set<String> {
    var out = Set<String>()
    guard let info = diskutilPlist(["info", "-plist", "/"]) else { return out }
    if let parent = info["ParentWholeDisk"] as? String {
      out.insert(parent)
      out.insert(wholeDiskId(parent))
    }
    if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
      for store in stores {
        if let ident = store["APFSPhysicalStore"] as? String {
          out.insert(ident)
          out.insert(wholeDiskId(ident))
        }
      }
    }
    return out
  }
}

private struct MountTable {
  var fusePoints: Set<String>
}

private func currentMounts() -> MountTable {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
  proc.standardOutput = Pipe()
  proc.standardError = Pipe()
  try? proc.run()
  proc.waitUntilExit()
  let data = (proc.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  let text = String(data: data, encoding: .utf8) ?? ""
  var fuse = Set<String>()
  for line in text.split(separator: "\n") {
    let s = String(line)
    let lower = s.lowercased()
    guard lower.contains("macfuse")
      || lower.contains("osxfuse")
      || lower.contains("fuse-t")
      || lower.contains("fuset")
      || lower.contains("ntfs-3g")
      || s.contains(" fuse,")
    else { continue }
    if let range = s.range(of: " on "),
       let end = s.range(of: " (") {
      fuse.insert(String(s[range.upperBound..<end.lowerBound]))
    }
  }
  return MountTable(fusePoints: fuse)
}

private func diskutilPlist(_ args: [String]) -> [String: Any]? {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
  proc.arguments = args
  let out = Pipe()
  proc.standardOutput = out
  proc.standardError = Pipe()
  do {
    try proc.run()
    proc.waitUntilExit()
  } catch {
    return nil
  }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
}

enum Privileged {
  static let helperCandidates = [
    "/usr/local/sbin/ntfs-rw-helper",
    Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil),
  ].compactMap { $0 }

  static var systemHelperInstalled: Bool {
    FileManager.default.isExecutableFile(atPath: "/usr/local/sbin/ntfs-rw-helper")
  }

  static var autoMountEnabled: Bool {
    FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/local.ntfsmount.automount.plist")
  }

  static var helperNeedsUpdate: Bool {
    guard systemHelperInstalled,
          let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil)
    else { return false }
    let a = try? Data(contentsOf: URL(fileURLWithPath: bundled))
    let b = try? Data(contentsOf: URL(fileURLWithPath: "/usr/local/sbin/ntfs-rw-helper"))
    guard let a, let b else { return false }
    return a != b
  }

  static var helperPath: String? {
    helperCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  struct Outcome {
    let ok: Bool
    let text: String
  }

  static func installHelper() -> Outcome {
    guard let installer = Bundle.main.path(forResource: "install-helper", ofType: "sh"),
          let helper = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil)
    else {
      return Outcome(ok: false, text: "应用包内缺少安装脚本，请重新安装。")
    }
    let user = NSUserName()
    let source = """
    do shell script "bash " & quoted form of "\(installer)" & " " & quoted form of "\(helper)" & " " & quoted form of "\(user)" with administrator privileges
    """
    let osa = Process()
    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osa.arguments = ["-e", source]
    let osaOut = Pipe()
    let osaErr = Pipe()
    osa.standardOutput = osaOut
    osa.standardError = osaErr
    do {
      try osa.run()
      osa.waitUntilExit()
      let out = String(data: osaOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let err = String(data: osaErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if osa.terminationStatus == 0 {
        return Outcome(ok: true, text: "挂载助手已安装")
      }
      return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
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
    guard let helper = helperPath else {
      return Outcome(ok: false, text: "未找到挂载助手。请点菜单「安装挂载助手」。")
    }
    let sudo = Process()
    sudo.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    sudo.arguments = ["-n", helper] + args
    let sudoOut = Pipe()
    let sudoErr = Pipe()
    sudo.standardOutput = sudoOut
    sudo.standardError = sudoErr
    do {
      try sudo.run()
      sudo.waitUntilExit()
      let out = String(data: sudoOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let err = String(data: sudoErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if sudo.terminationStatus == 0 {
        return Outcome(ok: true, text: out.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      if !err.lowercased().contains("password") && sudo.terminationStatus != 1 {
        return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
      }
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }

    let osa = Process()
    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osa.arguments = ["-e", adminShellScript(helper, args)]
    let osaOut = Pipe()
    let osaErr = Pipe()
    osa.standardOutput = osaOut
    osa.standardError = osaErr
    do {
      try osa.run()
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

  private static func adminShellScript(_ executable: String, _ args: [String]) -> String {
    func quoted(_ s: String) -> String {
      let escaped = s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      return "quoted form of \"\(escaped)\""
    }
    var expr = quoted(executable)
    for a in args {
      expr += " & \" \" & " + quoted(a)
    }
    return "do shell script " + expr + " with administrator privileges"
  }
}

struct MenuRoot: View {
  @ObservedObject var store: VolumeStore

  var body: some View {
    Button("打开窗口") { store.showMainWindow() }
      .keyboardShortcut("o")
    Divider()
    if store.volumes.isEmpty {
      Text("没有检测到 NTFS 硬盘")
      Text(store.formatDisks.isEmpty
        ? "插入 Windows 格式的移动盘后再点菜单"
        : "可用「格式化为 NTFS」把其他移动盘转成 NTFS")
        .foregroundStyle(.secondary)
    } else {
      ForEach(store.volumes) { vol in
        Menu {
          Button("以可写方式挂载") { store.mount(vol) }
            .disabled(vol.isWritableFuse || store.busyId != nil)
          Button("在访达中打开") {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
          .disabled(vol.mountPoint.isEmpty)
          Divider()
          Button("卸载") { store.unmount(vol) }
            .disabled(vol.mountPoint.isEmpty || store.busyId != nil)
          Button("推出（可安全拔出）") { store.eject(vol) }
            .disabled(store.busyId != nil)
          Divider()
          Button("格式化为 NTFS…") {
            if let disk = store.formatDisks.first(where: { $0.id == wholeDiskId(vol.id) }) {
              store.confirmFormat(disk)
            }
          }
          .disabled(store.busyId != nil || !store.formatDisks.contains(where: { $0.id == wholeDiskId(vol.id) }))
        } label: {
          Text("\(statusDot(vol)) \(vol.name)  ·  \(vol.stateLabel)  ·  \(vol.sizeLabel)")
        }
      }
      Divider()
      Button("全部以可写方式挂载") { store.mountAll() }
        .keyboardShortcut("m")
        .disabled(store.volumes.allSatisfy(\.isWritableFuse) || store.busyId != nil)
    }
    if !store.formatDisks.isEmpty {
      Divider()
      Menu("格式化为 NTFS…") {
        ForEach(store.formatDisks) { disk in
          Button("\(disk.name)  ·  \(disk.fsHint)  ·  \(disk.sizeLabel)") {
            store.confirmFormat(disk)
          }
          .disabled(store.busyId != nil)
        }
      }
    }
    Divider()
    Button("刷新") { store.refresh() }
      .keyboardShortcut("r")
    Button(store.launchAtLogin ? "开机启动：开" : "开机启动：关") {
      store.toggleLogin()
    }
    Button(store.autoMount ? "插入时自动挂载：开" : "插入时自动挂载：关") {
      store.toggleAutoMount()
    }
    .disabled(store.busyId != nil || !store.helperInstalled || Privileged.helperNeedsUpdate)
    if !store.helperInstalled {
      Button("安装挂载助手…") { store.installHelper() }
    } else if Privileged.helperNeedsUpdate {
      Button("更新挂载助手…") { store.installHelper() }
    }
    Text(MacOSCompat.menuCaption)
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(2)
    if !store.message.isEmpty {
      Text(store.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }
    Divider()
    Button("退出 NTFS 读写") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }

  private func statusDot(_ vol: NTFSVolume) -> String {
    if store.busyId == vol.id { return "…" }
    if vol.isWritableFuse { return "●" }
    if vol.isReadOnlyMounted { return "○" }
    return "◌"
  }
}
