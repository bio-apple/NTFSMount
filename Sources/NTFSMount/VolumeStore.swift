import AppKit
import NTFSMountCore
import ServiceManagement
import SwiftUI

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
  @Published var openSettings = false

  private var timer: Timer?
  private var diskWatch = DiskWatch()
  private var skippedUnmount = Set<String>()
  private var autoMountAttempted = Set<String>()
  private var lastAdvice: [String: VolumeHealth.MountAdvice] = [:]

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
      LegalGate.confirmOrTerminate()
      self?.presentWindowOnFirstLaunch()
      self?.offerHelperUpdateIfNeeded()
      self?.enableAutoMountDefault()
    }
  }

  deinit {
    timer?.invalidate()
    diskWatch.stop()
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

  func statusLabel(_ vol: NTFSVolume) -> String {
    VolumeHealth.shortStatus(
      busy: busyId == vol.id,
      isWritableFuse: vol.isWritableFuse,
      isReadOnlyMounted: vol.isReadOnlyMounted,
      lastAdvice: lastAdvice[vol.id]
    )
  }

  func detailStatus(_ vol: NTFSVolume) -> String {
    VolumeHealth.detailStatus(
      isWritableFuse: vol.isWritableFuse,
      isReadOnlyMounted: vol.isReadOnlyMounted,
      lastAdvice: lastAdvice[vol.id]
    )
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
    message = display(result.text)
    if result.ok {
      UserDefaults.standard.set(false, forKey: AppIdentity.Defaults.autoMountUserOff)
      if let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil) {
        UserDefaults.standard.set(AppIdentity.sha256File(bundled), forKey: AppIdentity.Defaults.lastHelperSHA)
      }
      Thread.sleep(forTimeInterval: 0.5)
      helperInstalled = Privileged.systemHelperInstalled
      enableAutoMountDefault()
    }
  }

  func uninstallHelper() {
    let result = Privileged.uninstallHelper()
    helperInstalled = Privileged.systemHelperInstalled
    autoMount = Privileged.autoMountEnabled
    message = display(result.text)
  }

  func confirmUninstallHelper() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "卸载挂载助手？"
    alert.informativeText = "将删除特权守护进程和插入时自动挂载。应用仍留在「应用程序」里。"
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: "卸载助手")
    makeCancelDefault(alert)
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
    捆绑 ntfs-3g / mkntfs（GPL-2.0）以及 FUSE-T 的 go-nfsv4。go-nfsv4 仅供个人使用；作为产品分发须向 FUSE-T 取得许可。

    写 NTFS 有损坏数据的风险，请先备份。

    当前构建\(SigningStatus.isNotarized ? "已公证。" : "未公证（Gatekeeper 可能拦截）。按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。")
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

  func showSettings() {
    openSettings = true
    showMainWindow()
  }

  func refresh() {
    volumes = NTFSVolume.scan()
    formatDisks = FormatDisk.scan()
    autoMount = Privileged.autoMountEnabled
    helperInstalled = Privileged.systemHelperInstalled
    let ids = Set(volumes.map(\.id))
    skippedUnmount.formIntersection(ids)
    autoMountAttempted.formIntersection(ids)
    lastAdvice = lastAdvice.filter { ids.contains($0.key) }
    for vol in volumes where vol.isWritableFuse {
      lastAdvice[vol.id] = .writable
    }
    mountDefaultWritableIfNeeded()
  }

  func mount(_ vol: NTFSVolume, openFinder: Bool = true) {
    if vol.isInternal, !confirmInternalMount(vol) { return }
    if !LegalGate.confirmWritable() { return }
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
    if !LegalGate.confirmWritable() { return }
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
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: "仍然挂载")
    makeCancelDefault(alert)
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
    alert.informativeText = """
    \(FormatPolicy.identityLines(
      sizeLabel: disk.sizeLabel,
      deviceId: disk.id,
      serial: disk.serial,
      fsHint: disk.fsHint,
      mediaName: disk.mediaName
    ))
    将删除盘上全部文件，且无法恢复。
    第一行输入「\(disk.name)」确认，第二行是新卷名。
    """
    alert.accessoryView = box
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: FormatPolicy.formatTitle)
    makeCancelDefault(alert)
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    guard FormatPolicy.confirms(typed: confirm.stringValue, currentName: disk.name) else {
      message = "未输入正确卷名，已取消格式化。"
      return
    }

    let again = NSAlert()
    again.alertStyle = .critical
    again.messageText = "最后确认：抹掉这张盘？"
    again.informativeText = FormatPolicy.finalWarning(
      name: disk.name,
      sizeLabel: disk.sizeLabel,
      deviceId: disk.id,
      serial: disk.serial
    )
    again.addButton(withTitle: FormatPolicy.cancelTitle)
    again.addButton(withTitle: FormatPolicy.formatTitle)
    makeCancelDefault(again)
    guard again.runModal() == .alertSecondButtonReturn else { return }
    format(disk, label: FormatPolicy.sanitizeLabel(label.stringValue))
  }

  private func makeCancelDefault(_ alert: NSAlert) {
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = ""
    }
    if let cancel = alert.buttons.first {
      cancel.keyEquivalent = "\r"
    }
  }

  func format(_ disk: FormatDisk, label: String) {
    busyId = disk.id
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run("format", disk.id, extra: [label])
      DispatchQueue.main.async {
        self.busyId = nil
        self.message = self.display(result.text)
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
        if !result.ok { self.message = self.display(result.text) }
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
          self.message = self.display(result.text)
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
        if cmd == "mount" {
          self.lastAdvice[vol.id] = VolumeHealth.advice(for: result.text, success: result.ok)
        }
        let shown = self.display(result.text)
        if result.ok {
          self.message = shown
          self.refresh()
          if cmd == "mount", openFinder {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
        } else {
          self.message = shown
          self.refresh()
          if cmd == "mount", VolumeHealth.looksLikeKextOrFSKitBlock(result.text) {
            self.alertKextIgnored(shown)
          }
        }
      }
    }
  }

  private func display(_ raw: String) -> String {
    if raw.count > 180 { AppLog.append("raw: \(raw)") }
    return UserFacingError.message(from: raw, logPath: AppLog.url.path)
  }
}
