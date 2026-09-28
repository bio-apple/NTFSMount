import AppKit
import NTFSMountCore
import ServiceManagement
import SwiftUI

/// Sendable hop so Timer / DiskWatch do not capture isolated `self` in a concurrent Task.
private final class RefreshHop: @unchecked Sendable {
  weak var store: VolumeStore?
  func ping() {
    Task { @MainActor [weak store = self.store] in
      store?.refresh()
    }
  }
}

enum VolumeActionCopy {
  static var ejectHelp: String { L10n.t("help.eject") }
  static var unmountHelp: String { L10n.t("help.unmount") }
}

@MainActor
final class VolumeStore: ObservableObject {
  @Published var volumes: [NTFSVolume] = []
  @Published var message: String = ""
  @Published var messageVolumeId: String?
  @Published var busyId: String?
  @Published var helperInstalled: Bool = Privileged.systemHelperInstalled
  @Published var helperInstallBusy = false
  @Published var formatDisks: [FormatDisk] = []
  @Published var encryptedDisks: [PossibleEncryptedDisk] = []
  @Published var autoMount: Bool = Privileged.autoMountEnabled
  @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
  @Published var showDock: Bool = UserDefaults.standard.bool(forKey: AppIdentity.Defaults.showDock)
  @Published var openSettings = false
  @Published var driverVersionLine: String = Ntfs3gVersion.settingsChecking
  @Published var driverVersionUntested = false

  private var timer: Timer?
  private var diskWatch = DiskWatch()
  private var skippedUnmount = Set<String>()
  private var autoMountAttempted = Set<String>()
  private var autoMountQueue: [String] = []
  private var autoMountPumping = false
  private var lastAdvice: [String: VolumeHealth.MountAdvice] = [:]
  private var lastHelperText: [String: String] = [:]
  private var volumeMessages: [String: String] = [:]
  private var lastFailedCmd: [String: String] = [:]
  private var refreshRunning = false
  private var refreshQueued = false
  private let refreshHop = RefreshHop()
  private var cachedNtfs3g: Ntfs3gVersion.Parsed?

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
    refreshHop.store = self
    refresh()
    diskWatch.onChange = { [hop = refreshHop] in hop.ping() }
    diskWatch.start()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [hop = refreshHop] _ in
      hop.ping()
    }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let parsed = EnvironmentDiagnoseRunner.probeNtfs3g()
      DispatchQueue.main.async { self?.applyDriverVersion(parsed) }
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
    alert.messageText = L10n.t("alert.updateHelperTitle")
    alert.informativeText = L10n.t("alert.updateHelperBody")
    alert.addButton(withTitle: L10n.t("alert.update"))
    alert.addButton(withTitle: L10n.t("later"))
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

  func volumeMessage(_ vol: NTFSVolume) -> String {
    volumeMessages[vol.id] ?? ""
  }

  func failedCommand(_ vol: NTFSVolume) -> String? {
    lastFailedCmd[vol.id]
  }

  func canMountWritable(_ vol: NTFSVolume) -> Bool {
    helperInstalled && !isHibernated(vol) && !Privileged.helperNeedsUpdate
  }

  func writableMountHelp(_ vol: NTFSVolume) -> String {
    if !helperInstalled { return L10n.t("mount.needHelper") }
    if Privileged.helperNeedsUpdate { return L10n.t("mount.needUpdate") }
    if isHibernated(vol) {
      return VolumeHealth.detailStatus(
        isWritableFuse: false,
        isReadOnlyMounted: true,
        lastAdvice: .readOnlyDirty
      )
    }
    return L10n.t("mount.writableHelp")
  }

  func isHibernated(_ vol: NTFSVolume) -> Bool {
    lastAdvice[vol.id] == .readOnlyDirty
      && VolumeHealth.looksHibernated(lastHelperText[vol.id] ?? "")
  }

  func alertKextIgnored(_ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = L10n.t("alert.mountFailed")
    alert.informativeText = L10n.format("alert.kextBody", detail)
    alert.addButton(withTitle: L10n.t("ok.gotIt"))
    alert.runModal()
  }

  func installHelper() {
    guard !helperInstallBusy else { return }
    helperInstallBusy = true
    setMessage(L10n.t("installing"))
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Privileged.installHelper()
      DispatchQueue.main.async {
        guard let self else { return }
        self.helperInstallBusy = false
        self.helperInstalled = Privileged.systemHelperInstalled
        self.setMessage(self.display(result.text))
        if result.ok {
          UserDefaults.standard.set(false, forKey: AppIdentity.Defaults.autoMountUserOff)
          if let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil) {
            UserDefaults.standard.set(AppIdentity.sha256File(bundled), forKey: AppIdentity.Defaults.lastHelperSHA)
          }
          self.waitForHelperSocketThenFinishInstall()
        }
      }
    }
  }

  private func waitForHelperSocketThenFinishInstall() {
    let path = AppIdentity.helperSocket
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let deadline = Date().addingTimeInterval(5)
      while !FileManager.default.fileExists(atPath: path), Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }
      DispatchQueue.main.async {
        guard let self else { return }
        self.helperInstalled = Privileged.systemHelperInstalled
        self.enableAutoMountDefault()
      }
    }
  }

  func uninstallHelper() {
    let result = Privileged.uninstallHelper()
    helperInstalled = Privileged.systemHelperInstalled
    autoMount = Privileged.autoMountEnabled
    setMessage(display(result.text))
  }

  func confirmUninstallHelper() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("alert.uninstallTitle")
    alert.informativeText = L10n.t("alert.uninstallBody")
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: L10n.t("alert.uninstall"))
    makeCancelDefault(alert)
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    uninstallHelper()
  }

  func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = AppIdentity.productName
    let signingLine = SigningStatus.isNotarized
      ? L10n.t("about.notarized")
      : L10n.t("about.unnotarized")
    alert.informativeText = UpdateCopy.aboutPrivacy(
      logPath: AppLog.url.path,
      sourceURL: AppIdentity.sourceURL,
      signingLine: signingLine
    )
    alert.addButton(withTitle: L10n.t("ok.gotIt"))
    alert.addButton(withTitle: L10n.t("about.openSource"))
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

  private func applyDriverVersion(_ parsed: Ntfs3gVersion.Parsed) {
    cachedNtfs3g = parsed
    driverVersionLine = Ntfs3gVersion.settingsLine(parsed)
    driverVersionUntested = parsed.status == .untested
  }

  func confirmDriverIfNeeded() -> Bool {
    let parsed = cachedNtfs3g ?? EnvironmentDiagnoseRunner.probeNtfs3g()
    applyDriverVersion(parsed)
    return LegalGate.confirmUntestedDriver(parsed)
  }

  func refresh() {
    if refreshRunning {
      refreshQueued = true
      return
    }
    refreshRunning = true
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let volumes = NTFSVolume.scan()
      let formatDisks = FormatDisk.scan()
      let encrypted = EncryptedDiskHint.scan()
      DispatchQueue.main.async {
        self?.applyScan(volumes: volumes, formatDisks: formatDisks, encrypted: encrypted)
      }
    }
  }

  private func applyScan(
    volumes: [NTFSVolume],
    formatDisks: [FormatDisk],
    encrypted: [PossibleEncryptedDisk]
  ) {
    self.volumes = volumes
    self.formatDisks = formatDisks
    encryptedDisks = encrypted
    autoMount = Privileged.autoMountEnabled
    helperInstalled = Privileged.systemHelperInstalled
    let ids = Set(volumes.map(\.id))
    skippedUnmount.formIntersection(ids)
    autoMountAttempted.formIntersection(ids)
    lastAdvice = lastAdvice.filter { ids.contains($0.key) }
    lastHelperText = lastHelperText.filter { ids.contains($0.key) }
    volumeMessages = volumeMessages.filter { ids.contains($0.key) }
    lastFailedCmd = lastFailedCmd.filter { ids.contains($0.key) }
    for vol in volumes where vol.isWritableFuse {
      lastAdvice[vol.id] = .writable
    }
    mountDefaultWritableIfNeeded()
    refreshRunning = false
    if refreshQueued {
      refreshQueued = false
      refresh()
    }
  }

  func canOfferDirtyFix(_ vol: NTFSVolume) -> Bool {
    !vol.isInternal
      && lastAdvice[vol.id] == .readOnlyDirty
      && VolumeHealth.canOfferDirtyFix(lastHelperText[vol.id] ?? "")
  }

  func confirmDirtyFix(_ vol: NTFSVolume) {
    guard canOfferDirtyFix(vol) else { return }
    guard presentNtfsfixConsent(vol) else { return }
    fixDirtyThenMount(vol)
  }

  @discardableResult
  private func presentNtfsfixConsent(_ vol: NTFSVolume) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("dirty.title")
    alert.informativeText = L10n.format("dirty.body", vol.name)
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: L10n.t("dirty.fix"))
    makeCancelDefault(alert)
    return alert.runModal() == .alertSecondButtonReturn
  }

  private func fixDirtyThenMount(_ vol: NTFSVolume) {
    busyId = vol.id
    setMessage("", volumeId: vol.id)
    DispatchQueue.global(qos: .userInitiated).async {
      let fixResult = Privileged.run("fix", vol.id)
      if !fixResult.ok {
        DispatchQueue.main.async {
          self.busyId = nil
          self.lastHelperText[vol.id] = fixResult.text
          if VolumeHealth.looksDirtyOrHibernated(fixResult.text) {
            self.lastAdvice[vol.id] = .readOnlyDirty
          }
          self.finishVolume(vol, cmd: "fix", result: fixResult, openFinder: false)
        }
        return
      }
      let mountResult = Privileged.run("mount", vol.id)
      DispatchQueue.main.async {
        self.busyId = nil
        self.lastAdvice[vol.id] = VolumeHealth.advice(for: mountResult.text, success: mountResult.ok)
        self.lastHelperText[vol.id] = mountResult.text
        self.finishVolume(vol, cmd: "mount", result: mountResult, openFinder: true)
      }
    }
  }

  func mount(_ vol: NTFSVolume, openFinder: Bool = true, fromAutoMount: Bool = false) {
    if vol.isInternal, !confirmInternalMount(vol) {
      if fromAutoMount { markAutoMountFinished(vol.id, userRefused: true, helperReturned: false) }
      return
    }
    if !LegalGate.confirmWritable() {
      if fromAutoMount { markAutoMountFinished(vol.id, userRefused: true, helperReturned: false) }
      return
    }
    if !confirmDriverIfNeeded() {
      if fromAutoMount { markAutoMountFinished(vol.id, userRefused: true, helperReturned: false) }
      return
    }
    skippedUnmount.remove(vol.id)
    if fromAutoMount {
      run("mount", vol, openFinder: openFinder, fromAutoMount: true)
      return
    }
    probeThenMount(vol, openFinder: openFinder)
  }

  private func probeThenMount(_ vol: NTFSVolume, openFinder: Bool) {
    busyId = vol.id
    setMessage(VolumeHealth.PreMountCopy.probingStatus, volumeId: vol.id)
    DispatchQueue.global(qos: .userInitiated).async {
      let probe = Privileged.run("probe", vol.id)
      DispatchQueue.main.async {
        self.lastHelperText[vol.id] = probe.text
        let kind = VolumeHealth.probeKind(from: probe.text)
        if kind == .hibernated || kind == .dirty || kind == .corrupt {
          self.lastAdvice[vol.id] = .readOnlyDirty
        }
        switch VolumeHealth.preMountDialog(for: kind) {
        case .none:
          self.run("mount", vol, openFinder: openFinder)
        case .hibernated:
          if self.confirmHiberReadOnly(vol) {
            self.run("mount", vol, openFinder: openFinder)
          } else {
            self.cancelAfterProbe(vol)
          }
        case .dirtyOrCorrupt:
          switch self.confirmDirtyOrCorrupt(vol) {
          case .readOnly:
            self.run("mount", vol, openFinder: openFinder)
          case .fixThenWritable:
            if self.presentNtfsfixConsent(vol) {
              self.fixDirtyThenMount(vol)
            } else {
              self.cancelAfterProbe(vol)
            }
          case .cancel:
            self.cancelAfterProbe(vol)
          }
        }
      }
    }
  }

  private func cancelAfterProbe(_ vol: NTFSVolume) {
    busyId = nil
    setMessage(L10n.t("error.canceled"), volumeId: vol.id)
    restoreSystemMount(vol)
  }

  private func restoreSystemMount(_ vol: NTFSVolume) {
    DispatchQueue.global(qos: .utility).async {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
      proc.arguments = ["mount", vol.id]
      proc.standardOutput = Pipe()
      proc.standardError = Pipe()
      try? proc.run()
      proc.waitUntilExit()
      DispatchQueue.main.async { self.refresh() }
    }
  }

  private func confirmHiberReadOnly(_ vol: NTFSVolume) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = VolumeHealth.PreMountCopy.hiberTitle
    alert.informativeText = VolumeHealth.PreMountCopy.hiberBody(volumeName: vol.name)
    alert.addButton(withTitle: VolumeHealth.PreMountCopy.readOnlyTitle)
    alert.addButton(withTitle: VolumeHealth.PreMountCopy.cancelTitle)
    makeSafeDefault(alert)
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func confirmDirtyOrCorrupt(_ vol: NTFSVolume) -> VolumeHealth.PreMountChoice {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = VolumeHealth.PreMountCopy.dirtyTitle
    alert.informativeText = VolumeHealth.PreMountCopy.dirtyBody(volumeName: vol.name)
    alert.addButton(withTitle: VolumeHealth.PreMountCopy.readOnlyTitle)
    alert.addButton(withTitle: VolumeHealth.PreMountCopy.fixThenWritableTitle)
    alert.addButton(withTitle: VolumeHealth.PreMountCopy.cancelTitle)
    makeSafeDefault(alert)
    switch alert.runModal() {
    case .alertFirstButtonReturn: return .readOnly
    case .alertSecondButtonReturn: return .fixThenWritable
    default: return .cancel
    }
  }

  func retry(_ vol: NTFSVolume) {
    let cmd = lastFailedCmd[vol.id] ?? "mount"
    switch cmd {
    case "eject": eject(vol)
    case "unmount": unmount(vol)
    case "fix": confirmDirtyFix(vol)
    default: mount(vol)
    }
  }

  func unmount(_ vol: NTFSVolume) {
    skippedUnmount.insert(vol.id)
    run("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) {
    if vol.isInternal {
      setMessage(L10n.t("eject.refuseInternal"), volumeId: vol.id)
      return
    }
    skippedUnmount.insert(vol.id)
    run("eject", vol)
  }

  func mountAll() {
    if !helperInstalled { return }
    if !LegalGate.confirmWritable() { return }
    if !confirmDriverIfNeeded() { return }
    for vol in volumes where !vol.isWritableFuse && !vol.isInternal && canMountWritable(vol) {
      run("mount", vol, openFinder: false)
    }
  }

  func confirmInternalMount(_ vol: NTFSVolume) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.t("internal.title")
    alert.informativeText = L10n.format("internal.body", vol.name)
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: L10n.t("internal.anyway"))
    makeCancelDefault(alert)
    return alert.runModal() == .alertSecondButtonReturn
  }

  func confirmFormat(_ disk: FormatDisk) {
    NSApp.activate(ignoringOtherApps: true)
    let fields = FormatConfirmFields(disk: disk)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.format("format.confirmTitle", disk.name)
    var info = FormatPolicy.identityLines(
      sizeLabel: disk.sizeLabel,
      deviceId: disk.id,
      serial: disk.serial,
      fsHint: disk.fsHint,
      mediaName: disk.mediaName
    )
    if let warn = disk.encryptionWarning {
      info += "\n\(warn)"
    }
    info += "\n" + L10n.format("format.confirmExtra", disk.name)
    alert.informativeText = info
    alert.accessoryView = fields.view
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    alert.addButton(withTitle: FormatPolicy.formatTitle)
    makeCancelDefault(alert)
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    guard FormatPolicy.confirms(typed: fields.confirm.stringValue, currentName: disk.name) else {
      let mismatch = NSAlert()
      mismatch.alertStyle = .warning
      mismatch.messageText = L10n.t("format.nameMismatch")
      mismatch.addButton(withTitle: L10n.t("ok"))
      mismatch.runModal()
      return
    }

    let again = NSAlert()
    again.alertStyle = .critical
    again.messageText = L10n.t("format.finalTitle")
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
    format(disk, label: FormatPolicy.sanitizeLabel(fields.label.stringValue))
  }

  private func makeCancelDefault(_ alert: NSAlert) {
    if alert.buttons.count > 1 {
      alert.buttons[1].keyEquivalent = ""
    }
    if let cancel = alert.buttons.first {
      cancel.keyEquivalent = "\r"
    }
  }

  private func makeSafeDefault(_ alert: NSAlert) {
    for (i, button) in alert.buttons.enumerated() {
      button.keyEquivalent = i == 0 ? "\r" : ""
    }
    if let last = alert.buttons.last, alert.buttons.count > 1 {
      last.keyEquivalent = "\u{1b}"
    }
  }

  func format(_ disk: FormatDisk, label: String) {
    busyId = disk.id
    setMessage("")
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run("format", disk.id, extra: [label])
      DispatchQueue.main.async {
        self.busyId = nil
        self.setMessage(self.display(result.text))
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
      setMessage(L10n.format("login.failed", error.localizedDescription))
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
    autoMount = Privileged.autoMountEnabled
    if Privileged.autoMountEnabled {
      mountDefaultWritableIfNeeded()
      return
    }
    guard AutoMountPolicy.shouldAutoEnable(
      helperInstalled: helperInstalled,
      legalAccepted: LegalGate.hasAcceptedLegal,
      writableStampPresent: FileManager.default.fileExists(atPath: AppIdentity.writableStampURL.path),
      userOptedOff: UserDefaults.standard.bool(forKey: AppIdentity.Defaults.autoMountUserOff)
    ) else { return }
    busyId = "automount"
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run("enable-automount")
      DispatchQueue.main.async {
        self.busyId = nil
        self.autoMount = Privileged.autoMountEnabled
        if !result.ok { self.setMessage(self.display(result.text)) } else { self.mountDefaultWritableIfNeeded() }
      }
    }
  }

  func mountDefaultWritableIfNeeded() {
    guard autoMount, helperInstalled, !Privileged.helperNeedsUpdate else { return }
    guard FileManager.default.fileExists(atPath: AppIdentity.writableStampURL.path) else { return }
    for vol in volumes {
      if AutoMountPolicy.isEligible(
        isInternal: vol.isInternal,
        isWritableFuse: vol.isWritableFuse,
        userSkippedUnmount: skippedUnmount.contains(vol.id),
        alreadyAttempted: autoMountAttempted.contains(vol.id)
      ), !autoMountQueue.contains(vol.id) {
        autoMountQueue.append(vol.id)
      }
    }
    pumpAutoMount()
  }

  private func pumpAutoMount() {
    guard !autoMountPumping else { return }
    guard busyId == nil else { return }
    autoMountQueue.removeAll { id in
      autoMountAttempted.contains(id) || !volumes.contains(where: { $0.id == id })
    }
    guard let id = autoMountQueue.first, let vol = volumes.first(where: { $0.id == id }) else { return }
    autoMountPumping = true
    mount(vol, openFinder: false, fromAutoMount: true)
  }

  private func markAutoMountFinished(_ id: String, userRefused: Bool, helperReturned: Bool) {
    if AutoMountPolicy.shouldRecordAttempt(userRefused: userRefused, helperReturned: helperReturned) {
      autoMountAttempted.insert(id)
    }
    autoMountQueue.removeAll { $0 == id }
    autoMountPumping = false
    if userRefused { pumpAutoMount() }
  }

  func toggleAutoMount() {
    let turningOff = autoMount
    let cmd = turningOff ? "disable-automount" : "enable-automount"
    busyId = "automount"
    setMessage("")
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd)
      DispatchQueue.main.async {
        self.busyId = nil
        self.autoMount = Privileged.autoMountEnabled
        if result.ok {
          UserDefaults.standard.set(turningOff, forKey: AppIdentity.Defaults.autoMountUserOff)
          self.setMessage(self.autoMount ? L10n.t("automount.enabled") : L10n.t("automount.disabled"))
          if self.autoMount { self.mountDefaultWritableIfNeeded() }
        } else {
          self.setMessage(self.display(result.text))
        }
      }
    }
  }

  private func run(_ cmd: String, _ vol: NTFSVolume, openFinder: Bool = false, fromAutoMount: Bool = false) {
    busyId = vol.id
    setMessage("", volumeId: vol.id)
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd, vol.id)
      DispatchQueue.main.async {
        self.busyId = nil
        if cmd == "mount" {
          self.lastAdvice[vol.id] = VolumeHealth.advice(for: result.text, success: result.ok)
          self.lastHelperText[vol.id] = result.text
        }
        if fromAutoMount {
          self.markAutoMountFinished(vol.id, userRefused: false, helperReturned: true)
        }
        self.finishVolume(vol, cmd: cmd, result: result, openFinder: openFinder)
      }
    }
  }

  private func finishVolume(
    _ vol: NTFSVolume,
    cmd: String,
    result: Privileged.Outcome,
    openFinder: Bool
  ) {
    let shown = display(result.text)
    setMessage(shown, volumeId: vol.id)
    if result.ok {
      lastFailedCmd[vol.id] = nil
    } else {
      lastFailedCmd[vol.id] = cmd
    }
    refresh()
    if result.ok, cmd == "mount", openFinder {
      NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
    } else if !result.ok, cmd == "mount", VolumeHealth.looksLikeKextOrFSKitBlock(result.text) {
      alertKextIgnored(shown)
    }
    if autoMountPumping == false { pumpAutoMount() }
  }

  private func setMessage(_ text: String, volumeId: String? = nil) {
    message = text
    messageVolumeId = volumeId
    if let volumeId {
      volumeMessages[volumeId] = text
    }
  }

  private func display(_ raw: String) -> String {
    if raw.count > 180 { AppLog.append("raw: \(raw)") }
    return UserFacingError.message(from: raw, logPath: AppLog.url.path)
  }
}

private struct FormatConfirmFields {
  let view: NSView
  let confirm: NSTextField
  let label: NSTextField

  init(disk: FormatDisk) {
    let currentCaption = NSTextField(labelWithString: L10n.t("format.currentName"))
    currentCaption.frame = NSRect(x: 0, y: 58, width: 320, height: 16)
    confirm = NSTextField(frame: NSRect(x: 0, y: 32, width: 320, height: 24))
    confirm.placeholderString = L10n.t("format.currentPlaceholder")
    let newCaption = NSTextField(labelWithString: L10n.t("format.newName"))
    newCaption.frame = NSRect(x: 0, y: 16, width: 320, height: 16)
    label = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    label.stringValue = disk.suggestedLabel
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 76))
    box.addSubview(currentCaption)
    box.addSubview(confirm)
    box.addSubview(newCaption)
    box.addSubview(label)
    view = box
  }
}
