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

  static var shouldShowLaunchNotice: Bool {
    !UserDefaults.standard.bool(forKey: AppIdentity.Defaults.didShowCompat)
  }

  static func markLaunchNoticeShown() {
    UserDefaults.standard.set(true, forKey: AppIdentity.Defaults.didShowCompat)
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
  @Published var helperInstalled: Bool = Privileged.systemHelperInstalled
  @Published var formatDisks: [FormatDisk] = []
  @Published var autoMount: Bool = Privileged.autoMountEnabled
  @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
  @Published var showDock: Bool = UserDefaults.standard.bool(forKey: AppIdentity.Defaults.showDock)

  private var timer: Timer?
  private var diskWatch = DiskWatch()
  private var skippedUnmount = Set<String>()
  private var autoMountAttempted = Set<String>()

  var writableCount: Int { volumes.filter(\.isWritableFuse).count }
  var menuBarTitle: String {
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
    AppIdentity.migrateDefaultsIfNeeded()
    applyDockPolicy()
    refresh()
    diskWatch.onChange = { [weak self] in
      Task { @MainActor in self?.refresh() }
    }
    diskWatch.start()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    DispatchQueue.main.async { [weak self] in
      PlatformGate.enforceOrTerminate()
      self?.presentWindowOnFirstLaunch()
      self?.offerHelperUpdateIfNeeded()
      self?.enableAutoMountDefault()
      self?.offerCompatNoticeIfNeeded()
    }
  }

  func presentWindowOnFirstLaunch() {
    let key = AppIdentity.Defaults.didShowWindow
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    UserDefaults.standard.set(true, forKey: key)
    showMainWindow()
  }

  func offerHelperUpdateIfNeeded() {
    guard helperInstalled, Privileged.helperNeedsUpdate else { return }
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
    if result.ok {
      UserDefaults.standard.set(false, forKey: AppIdentity.Defaults.autoMountUserOff)
      enableAutoMountDefault()
    }
  }

  func uninstallHelper() {
    let result = Privileged.uninstallHelper()
    helperInstalled = Privileged.systemHelperInstalled
    autoMount = Privileged.autoMountEnabled
    message = result.text
  }

  func confirmUninstallHelper() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "卸载挂载助手？"
    alert.informativeText = "将删除特权助手、sudo 规则和插入时自动挂载。应用仍留在「应用程序」里。"
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "卸载助手")
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    uninstallHelper()
  }

  func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = AppIdentity.productName
    alert.informativeText = """
    直发应用，不上 Mac App Store。

    隐私：不联网、不收集账户或通讯录。日志只写在本机：
    \(AppLog.url.path)

    源码与许可证：\(AppIdentity.sourceURL)
    捆绑 ntfs-3g / mkntfs（GPL-2.0）以及 FUSE-T 的 go-nfsv4。go-nfsv4 对个人使用免费；若把本应用作为产品分发，可能需要向 FUSE-T 取得商业许可。

    写 NTFS 有损坏数据的风险，请先备份。
    """
    alert.addButton(withTitle: "知道了")
    alert.addButton(withTitle: "打开源码页")
    if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: AppIdentity.sourceURL) {
      NSWorkspace.shared.open(url)
    }
  }

  func showMainWindow() {
    MainWindowController.shared.show(store: self)
  }

  func refresh() {
    volumes = NTFSVolume.scan()
    formatDisks = FormatDisk.scan()
    autoMount = Privileged.autoMountEnabled
    helperInstalled = Privileged.systemHelperInstalled
    let ids = Set(volumes.map(\.id))
    skippedUnmount.formIntersection(ids)
    autoMountAttempted.formIntersection(ids)
    mountDefaultWritableIfNeeded()
  }

  func mount(_ vol: NTFSVolume, openFinder: Bool = true) {
    if vol.isInternal, !confirmInternalMount(vol) { return }
    skippedUnmount.remove(vol.id)
    run("mount", vol, openFinder: openFinder)
  }

  func unmount(_ vol: NTFSVolume) {
    skippedUnmount.insert(vol.id)
    run("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) {
    skippedUnmount.insert(vol.id)
    run("eject", vol)
  }

  func mountAll() {
    for vol in volumes where !vol.isWritableFuse && !vol.isInternal {
      run("mount", vol, openFinder: false)
    }
  }

  func confirmInternalMount(_ vol: NTFSVolume) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "以可写方式挂载内置磁盘？"
    alert.informativeText = "「\(vol.name)」位于内置磁盘。可写挂载可能影响 Windows / Boot Camp 上的数据。"
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "仍然挂载")
    return alert.runModal() == .alertSecondButtonReturn
  }

  func confirmFormat(_ disk: FormatDisk) {
    NSApp.activate(ignoringOtherApps: true)
    let confirm = NSTextField(frame: NSRect(x: 0, y: 28, width: 280, height: 24))
    confirm.placeholderString = disk.name
    let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    label.stringValue = disk.suggestedLabel
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 52))
    box.addSubview(confirm)
    box.addSubview(label)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "抹掉「\(disk.name)」并格式化为 NTFS？"
    alert.informativeText = "\(disk.sizeLabel) · \(disk.id) · \(disk.fsHint)\n将删除盘上全部文件，且无法恢复。\n第一行输入「\(disk.name)」确认，第二行是新卷名。"
    alert.accessoryView = box
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "抹掉并格式化")
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    guard confirm.stringValue == disk.name else {
      message = "未输入正确卷名，已取消格式化。"
      return
    }
    format(disk, label: sanitizeLabel(label.stringValue))
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
      message = "登录时打开失败：\(error.localizedDescription)"
    }
  }

  func toggleDock() {
    showDock.toggle()
    UserDefaults.standard.set(showDock, forKey: AppIdentity.Defaults.showDock)
    applyDockPolicy()
  }

  func applyDockPolicy() {
    if showDock {
      NSApp.setActivationPolicy(.regular)
    }
  }

  func enableAutoMountDefault() {
    guard helperInstalled, !Privileged.autoMountEnabled else {
      autoMount = Privileged.autoMountEnabled
      if autoMount { mountDefaultWritableIfNeeded() }
      return
    }
    guard !UserDefaults.standard.bool(forKey: AppIdentity.Defaults.autoMountUserOff) else { return }
    busyId = "automount"
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run("enable-automount")
      DispatchQueue.main.async {
        self.busyId = nil
        self.autoMount = Privileged.autoMountEnabled
        if !result.ok { self.message = result.text }
        else { self.mountDefaultWritableIfNeeded() }
      }
    }
  }

  func mountDefaultWritableIfNeeded() {
    guard autoMount, helperInstalled, !Privileged.helperNeedsUpdate else { return }
    guard busyId == nil else { return }
    guard let vol = volumes.first(where: {
      !$0.isWritableFuse
        && !$0.isInternal
        && !skippedUnmount.contains($0.id)
        && !autoMountAttempted.contains($0.id)
    }) else { return }
    autoMountAttempted.insert(vol.id)
    mount(vol, openFinder: false)
  }

  func toggleAutoMount() {
    let turningOff = autoMount
    let cmd = turningOff ? "disable-automount" : "enable-automount"
    busyId = "automount"
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd)
      DispatchQueue.main.async {
        self.busyId = nil
        self.autoMount = Privileged.autoMountEnabled
        if result.ok {
          UserDefaults.standard.set(turningOff, forKey: AppIdentity.Defaults.autoMountUserOff)
          self.message = self.autoMount ? "已打开插入时自动挂载" : "已关闭插入时自动挂载"
          if self.autoMount { self.mountDefaultWritableIfNeeded() }
        } else {
          self.message = result.text
        }
      }
    }
  }

  private func run(_ cmd: String, _ vol: NTFSVolume, openFinder: Bool = false) {
    busyId = vol.id
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd, vol.id)
      DispatchQueue.main.async {
        self.busyId = nil
        if result.ok {
          self.message = result.text
          self.refresh()
          if cmd == "mount", openFinder {
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
  let isInternal: Bool
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
      let isInternalDisk = (info["Internal"] as? Bool == true)
        || (info["BusProtocol"] as? String == "Disk Image")
        || (info["BusProtocol"] as? String == "Apple Fabric")
      out.append(
        NTFSVolume(
          id: ident,
          name: volumeName,
          size: size,
          mountPoint: mp,
          isWritableFuse: fuse,
          isReadOnlyMounted: !mp.isEmpty && !fuse,
          isInternal: isInternalDisk,
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
    AppIdentity.helperPath,
    Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil),
  ].compactMap { $0 }

  static var systemHelperInstalled: Bool {
    FileManager.default.isExecutableFile(atPath: AppIdentity.helperPath)
  }

  static var autoMountEnabled: Bool {
    FileManager.default.fileExists(atPath: AppIdentity.daemonPlist)
      || FileManager.default.fileExists(atPath: AppIdentity.legacyDaemonPlist)
  }

  static var helperNeedsUpdate: Bool {
    guard systemHelperInstalled,
          let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil)
    else { return false }
    let a = try? Data(contentsOf: URL(fileURLWithPath: bundled))
    let b = try? Data(contentsOf: URL(fileURLWithPath: AppIdentity.helperPath))
    guard let a, let b else { return true }
    return a != b
  }

  static var helperPath: String? {
    if systemHelperInstalled, !helperNeedsUpdate {
      return AppIdentity.helperPath
    }
    return helperCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
    return runAdmin("bash \(quotedForShell(installer)) \(quotedForShell(helper)) \(quotedForShell(NSUserName()))")
  }

  static func uninstallHelper() -> Outcome {
    guard let script = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh") else {
      return Outcome(ok: false, text: "应用包内缺少卸载脚本。")
    }
    return runAdmin("bash \(quotedForShell(script))")
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
    guard let helper = helperPath else {
      return Outcome(ok: false, text: "未找到挂载助手。请点「安装挂载助手」。")
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

    return runAdmin(adminCommand(helper, args))
  }

  private static func runAdmin(_ shell: String) -> Outcome {
    let source = "do shell script \(appleScriptQuoted(shell)) with administrator privileges"
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
        return Outcome(ok: true, text: out.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }
  }

  private static func quotedForShell(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func appleScriptQuoted(_ s: String) -> String {
    "quoted form of \"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
  }

  private static func adminCommand(_ executable: String, _ args: [String]) -> String {
    ([executable] + args).map(quotedForShell).joined(separator: " ")
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
          if !vol.isWritableFuse {
            Button(vol.isInternal ? "以可写方式挂载（内置盘，需确认）" : "以可写方式挂载") {
              store.mount(vol)
            }
            .disabled(store.busyId != nil)
          }
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
          Text("\(statusLabel(vol))  ·  \(vol.name)  ·  \(vol.sizeLabel)")
        }
      }
      Divider()
      Button("全部以可写方式挂载") { store.mountAll() }
        .keyboardShortcut("m")
        .disabled(store.volumes.filter({ !$0.isInternal }).allSatisfy(\.isWritableFuse) || store.busyId != nil)
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
    Button(store.autoMount ? "插入时自动挂载：开" : "插入时自动挂载：关") {
      store.toggleAutoMount()
    }
    .disabled(store.busyId != nil || !store.helperInstalled || Privileged.helperNeedsUpdate)
    Button(store.launchAtLogin ? "登录时打开：开" : "登录时打开：关") {
      store.toggleLogin()
    }
    Button(store.showDock ? "在程序坞显示：开" : "在程序坞显示：关") {
      store.toggleDock()
    }
    if !store.helperInstalled {
      Button("安装挂载助手…") { store.installHelper() }
    } else if Privileged.helperNeedsUpdate {
      Button("更新挂载助手…") { store.installHelper() }
    } else {
      Button("卸载挂载助手…") { store.confirmUninstallHelper() }
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
    Button("关于与隐私…") { store.showAbout() }
    Button("退出 NTFS 读写") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }

  private func statusLabel(_ vol: NTFSVolume) -> String {
    if store.busyId == vol.id { return "处理中" }
    if vol.isWritableFuse { return "可写" }
    if vol.isReadOnlyMounted { return "只读" }
    return "未挂载"
  }
}
