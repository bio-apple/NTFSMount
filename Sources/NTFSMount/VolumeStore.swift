import AppKit
import NTFSMountCore
import ServiceManagement
import SwiftUI
import os

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
  private var mountAllQueue: [String] = []
  private var mountAllPumping = false
  private var lastAdvice: [String: VolumeHealth.MountAdvice] = [:]
  private var lastHelperText: [String: String] = [:]
  private var lastProbeKind: [String: VolumeHealth.ProbeKind] = [:]
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
    if volumes.contains(where: { lastAdvice[$0.id] == .readOnlyDirty }) {
      return "externaldrive.badge.exclamationmark"
    }
    if volumes.contains(where: { $0.isReadOnlyMounted }) {
      return "externaldrive.fill.badge.questionmark"
    }
    return "externaldrive"
  }

  var menuBarTooltip: String { MenuBarTooltip.extra(volumes) }

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
    Task { _ = await installHelper() }
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

  func diskStatusRows(_ vol: NTFSVolume) -> [DiskStatus.Row] {
    DiskStatus.rows(
      volume: vol,
      probeKind: lastProbeKind[vol.id],
      lastAdvice: lastAdvice[vol.id],
      helperText: lastHelperText[vol.id] ?? "",
      hasEncryptionHint: vol.hasEncryptionHint
        || encryptedDisks.contains(where: { $0.id == vol.id })
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

  @discardableResult
  func installHelper(then completion: ((Privileged.Outcome) -> Void)? = nil) async -> Privileged.Outcome {
    guard !helperInstallBusy else {
      let busy = Privileged.Outcome(ok: false, text: L10n.t("installing"))
      completion?(busy)
      return busy
    }
    helperInstallBusy = true
    setMessage(L10n.t("installing"))
    Privileged.prepareForAdminPrompt()
    await Task.yield()
    let result = await Privileged.installHelper()
    let finished = await finishInstallHelper(result)
    completion?(finished)
    return finished
  }

  private func finishInstallHelper(_ result: Privileged.Outcome) async -> Privileged.Outcome {
    helperInstalled = Privileged.systemHelperInstalled
    if result.ok {
      UserDefaults.standard.set(false, forKey: AppIdentity.Defaults.autoMountUserOff)
      setMessage(display(result.text))
      if Privileged.daemonReady {
        markHelperSHAMatched()
        helperInstallBusy = false
        enableAutoMountDefault()
        return result
      }
      return await waitForHelperSocketThenFinishInstall(successText: result.text)
    }
    helperInstallBusy = false
    AppLog.append("install-helper failed: \(result.text)")
    AppLog.helper.error("install-helper failed")
    setMessage(installFailureMessage(result.text))
    return result
  }

  private func markHelperSHAMatched() {
    if let bundled = Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil) {
      UserDefaults.standard.set(AppIdentity.sha256File(bundled), forKey: AppIdentity.Defaults.lastHelperSHA)
    }
  }

  private func installFailureMessage(_ raw: String) -> String {
    UserFacingError.message(from: raw, logPath: AppLog.url.path)
  }

  private func waitForHelperSocketThenFinishInstall(successText: String) async -> Privileged.Outcome {
    let path = AppIdentity.helperSocket
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: path), Date() < deadline {
          Thread.sleep(forTimeInterval: 0.1)
        }
        continuation.resume()
      }
    }
    helperInstalled = Privileged.systemHelperInstalled
    helperInstallBusy = false
    if Privileged.daemonReady {
      markHelperSHAMatched()
      enableAutoMountDefault()
      return Privileged.Outcome(ok: true, text: successText)
    }
    let fail = Privileged.Outcome(ok: false, text: Privileged.failedInstallText(successText))
    AppLog.append("install-helper: socket missing after wait")
    AppLog.helper.error("install-helper socket missing after wait")
    setMessage(installFailureMessage(fail.text))
    return fail
  }

  func uninstallHelper() async {
    helperInstallBusy = true
    defer { helperInstallBusy = false }
    let result = await Privileged.uninstallHelper()
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
    Task { await uninstallHelper() }
  }

  @discardableResult
  func confirmRepairMountEnvironment(then completion: ((Privileged.Outcome) -> Void)? = nil) -> Bool {
    if !helperInstalled {
      let text = L10n.t("error.helperMissing")
      setMessage(text)
      completion?(Privileged.Outcome(ok: false, text: text))
      return false
    }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = RepairMountCopy.title()
    alert.informativeText = RepairMountCopy.body()
    alert.addButton(withTitle: RepairMountCopy.cancelTitle)
    alert.addButton(withTitle: RepairMountCopy.actionTitle)
    makeCancelDefault(alert)
    guard alert.runModal() == .alertSecondButtonReturn else { return false }
    Task { @MainActor in
      let result = await self.repairMountEnvironment()
      completion?(result)
    }
    return true
  }

  func repairMountEnvironment() async -> Privileged.Outcome {
    if busyId != nil {
      return Privileged.Outcome(ok: false, text: message)
    }
    busyId = "repair"
    setMessage(L10n.t("repairEnv.working"))
    defer { busyId = nil }
    if Privileged.helperNeedsUpdate {
      let shown = L10n.t("privileged.mismatch")
      setMessage(shown)
      return Privileged.Outcome(ok: false, text: shown)
    }
    var helper = await Privileged.run("repair-env")
    var restarted = false
    if Privileged.systemHelperInstalled {
      if !helper.ok {
        _ = await Privileged.restartHelper()
        if Privileged.daemonReady {
          helper = await Privileged.run("repair-env")
        }
      }
      restarted = (await Privileged.restartHelper()).ok
    }
    let shown = RepairMountCopy.userMessage(
      helperText: helper.text,
      helperOK: helper.ok,
      helperRestarted: restarted
    )
    helperInstalled = Privileged.systemHelperInstalled
    AppLog.append("repair-env\n\(helper.text)\n\(shown)")
    AppLog.helper.info("repair-env ok=\(helper.ok, privacy: .public)")
    setMessage(shown)
    refresh()
    return Privileged.Outcome(ok: helper.ok, text: shown)
  }

  func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = AppIdentity.productName
    let signingLine = SigningStatus.isNotarized
      ? L10n.t("about.notarized")
      : L10n.t("about.unnotarized")
    alert.informativeText = AppVersion.line() + "\n\n" + UpdateCopy.aboutPrivacy(
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
    lastProbeKind = lastProbeKind.filter { ids.contains($0.key) }
    volumeMessages = volumeMessages.filter { ids.contains($0.key) }
    lastFailedCmd = lastFailedCmd.filter { ids.contains($0.key) }
    for vol in volumes where vol.isWritableFuse {
      lastAdvice[vol.id] = .writable
    }
    mountDefaultWritableIfNeeded()
    StatusItemTooltip.apply(menuBarTooltip)
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

  func confirmDirtyFix(_ vol: NTFSVolume) async {
    guard canOfferDirtyFix(vol) else { return }
    guard presentNtfsfixConsent(vol) else { return }
    await fixDirtyThenMount(vol)
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

  private func fixDirtyThenMount(_ vol: NTFSVolume) async {
    busyId = vol.id
    setMessage("", volumeId: vol.id)
    defer { busyId = nil }
    let fixResult = await Privileged.run("fix", vol.id)
    if !fixResult.ok {
      rememberHealthOutput(vol.id, fixResult.text)
      if VolumeHealth.looksDirtyOrHibernated(fixResult.text) {
        lastAdvice[vol.id] = .readOnlyDirty
      }
      await finishVolume(vol, cmd: "fix", result: fixResult, openFinder: false)
      return
    }
    let mountResult = await Privileged.run("mount", vol.id)
    lastAdvice[vol.id] = VolumeHealth.advice(for: mountResult.text, success: mountResult.ok)
    rememberHealthOutput(vol.id, mountResult.text)
    await finishVolume(vol, cmd: "mount", result: mountResult, openFinder: true)
  }

  func mount(_ vol: NTFSVolume, openFinder: Bool = true, fromAutoMount: Bool = false) async {
    if vol.isInternal {
      if fromAutoMount {
        markAutoMountFinished(vol.id, userRefused: true, helperReturned: false)
        return
      }
      if !confirmInternalMount(vol) { return }
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
      await run("mount", vol, openFinder: openFinder, fromAutoMount: true)
      return
    }
    await probeThenMount(vol, openFinder: openFinder)
  }

  private func probeThenMount(_ vol: NTFSVolume, openFinder: Bool) async {
    busyId = vol.id
    setMessage(VolumeHealth.PreMountCopy.probingStatus, volumeId: vol.id)
    let probe = await Privileged.run("probe", vol.id)
    rememberHealthOutput(vol.id, probe.text, fromProbe: true)
    if !probe.ok {
      busyId = nil
      await finishVolume(vol, cmd: "mount", result: probe, openFinder: false)
      await restoreSystemMount(vol)
      return
    }
    let kind = VolumeHealth.probeKind(from: probe.text)
    if kind == .hibernated || kind == .dirty || kind == .corrupt {
      lastAdvice[vol.id] = .readOnlyDirty
    }
    switch VolumeHealth.preMountDialog(for: kind) {
    case .none:
      await run("mount", vol, openFinder: openFinder)
    case .hibernated:
      if confirmHiberReadOnly(vol) {
        await run("mount", vol, openFinder: openFinder)
      } else {
        await cancelAfterProbe(vol)
      }
    case .dirtyOrCorrupt:
      switch confirmDirtyOrCorrupt(vol) {
      case .readOnly:
        await run("mount", vol, openFinder: openFinder)
      case .fixThenWritable:
        if presentNtfsfixConsent(vol) {
          await fixDirtyThenMount(vol)
        } else {
          await cancelAfterProbe(vol)
        }
      case .cancel:
        await cancelAfterProbe(vol)
      }
    }
  }

  private func cancelAfterProbe(_ vol: NTFSVolume) async {
    busyId = nil
    setMessage(L10n.t("error.canceled"), volumeId: vol.id)
    await restoreSystemMount(vol)
    advanceMountAll(after: vol.id)
  }

  private func restoreSystemMount(_ vol: NTFSVolume) async {
    let id = vol.id
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .utility).async {
        guard let diskutil = CommandPath.find("diskutil") else {
          continuation.resume()
          return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: diskutil)
        proc.arguments = ["mount", id]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        continuation.resume()
      }
    }
    refresh()
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

  func retry(_ vol: NTFSVolume) async {
    let cmd = lastFailedCmd[vol.id] ?? "mount"
    switch cmd {
    case "eject": await eject(vol)
    case "unmount": await unmount(vol)
    case "fix": await confirmDirtyFix(vol)
    default: await mount(vol)
    }
  }

  func unmount(_ vol: NTFSVolume) async {
    skippedUnmount.insert(vol.id)
    await run("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) async {
    if vol.isInternal {
      setMessage(L10n.t("eject.refuseInternal"), volumeId: vol.id)
      return
    }
    skippedUnmount.insert(vol.id)
    await run("eject", vol)
  }

  func mountAll() {
    if !helperInstalled { return }
    if !LegalGate.confirmWritable() { return }
    if !confirmDriverIfNeeded() { return }
    for vol in volumes where !vol.isWritableFuse && !vol.isInternal && canMountWritable(vol) {
      if !mountAllQueue.contains(vol.id) {
        mountAllQueue.append(vol.id)
      }
    }
    pumpMountAll()
  }

  private func pumpMountAll() {
    guard !mountAllPumping else { return }
    guard busyId == nil else { return }
    mountAllQueue.removeAll { id in
      guard let vol = volumes.first(where: { $0.id == id }) else { return true }
      return vol.isWritableFuse || vol.isInternal || !canMountWritable(vol)
    }
    guard let id = mountAllQueue.first, let vol = volumes.first(where: { $0.id == id }) else { return }
    mountAllPumping = true
    Task { await probeThenMount(vol, openFinder: false) }
  }

  private func advanceMountAll(after id: String) {
    mountAllQueue.removeAll { $0 == id }
    mountAllPumping = false
    pumpMountAll()
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
    Task { await format(disk, label: FormatPolicy.sanitizeLabel(fields.label.stringValue)) }
  }

  private func makeCancelDefault(_ alert: NSAlert) {
    applyKeyEquivalents(AlertDefaultPolicy.cancelDefault, to: alert)
  }

  private func makeSafeDefault(_ alert: NSAlert) {
    applyKeyEquivalents(AlertDefaultPolicy.safeDefault, to: alert)
  }

  private func applyKeyEquivalents(_ policy: AlertDefaultPolicy, to alert: NSAlert) {
    let count = alert.buttons.count
    for (i, button) in alert.buttons.enumerated() {
      button.keyEquivalent = policy.keyEquivalent(at: i, buttonCount: count)
    }
  }

  func format(_ disk: FormatDisk, label: String) async {
    busyId = disk.id
    setMessage("")
    let result = await Privileged.run("format", disk.id, extra: [label])
    busyId = nil
    setMessage(display(result.text))
    refresh()
    if result.ok, let vol = volumes.first(where: { wholeDiskId($0.id) == disk.id }) {
      await mount(vol)
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
    } else {
      NSApp.setActivationPolicy(.accessory)
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
    Task {
      let result = await Privileged.run("enable-automount")
      self.busyId = nil
      self.autoMount = Privileged.autoMountEnabled
      if !result.ok { self.setMessage(self.display(result.text)) } else { self.mountDefaultWritableIfNeeded() }
    }
  }

  func mountDefaultWritableIfNeeded() {
    guard AutoMountPolicy.mayAttempt(
      autoMountEnabled: autoMount,
      helperReady: helperInstalled && !Privileged.helperNeedsUpdate,
      legalAccepted: LegalGate.hasAcceptedLegal
    ) else { return }
    for vol in volumes {
      if AutoMountPolicy.isEligible(
        isInternal: vol.isInternal,
        isWritableFuse: vol.isWritableFuse,
        userSkippedUnmount: skippedUnmount.contains(vol.id),
        alreadyAttempted: autoMountAttempted.contains(vol.id)
      ), AutoMountPolicy.allowsWritableAttempt(lastProbeKind[vol.id] ?? .unknown),
         !autoMountQueue.contains(vol.id) {
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
    Task { await mount(vol, openFinder: false, fromAutoMount: true) }
  }

  private func markAutoMountFinished(_ id: String, userRefused: Bool, helperReturned: Bool) {
    if AutoMountPolicy.shouldRecordAttempt(userRefused: userRefused, helperReturned: helperReturned) {
      autoMountAttempted.insert(id)
    }
    autoMountQueue.removeAll { $0 == id }
    autoMountPumping = false
    if userRefused { pumpAutoMount() }
  }

  func toggleAutoMount() async {
    let turningOff = autoMount
    if !turningOff {
      guard helperInstalled, !Privileged.helperNeedsUpdate else { return }
      guard LegalGate.hasAcceptedLegal else { return }
      if !LegalGate.confirmWritable() { return }
      if !confirmDriverIfNeeded() { return }
    }
    let cmd = turningOff ? "disable-automount" : "enable-automount"
    busyId = "automount"
    setMessage("")
    defer { busyId = nil }
    let result = await Privileged.run(cmd)
    autoMount = Privileged.autoMountEnabled
    if result.ok {
      UserDefaults.standard.set(turningOff, forKey: AppIdentity.Defaults.autoMountUserOff)
      setMessage(autoMount ? L10n.t("automount.enabled") : L10n.t("automount.disabled"))
      if autoMount { mountDefaultWritableIfNeeded() }
    } else {
      setMessage(display(result.text))
    }
  }

  private func run(
    _ cmd: String,
    _ vol: NTFSVolume,
    openFinder: Bool = false,
    fromAutoMount: Bool = false,
    extra: [String] = []
  ) async {
    busyId = vol.id
    setMessage("", volumeId: vol.id)
    let result = await Privileged.run(cmd, vol.id, extra: extra)
    busyId = nil
    if cmd == "mount" {
      lastAdvice[vol.id] = VolumeHealth.advice(for: result.text, success: result.ok)
      rememberHealthOutput(vol.id, result.text)
    }
    if fromAutoMount {
      markAutoMountFinished(vol.id, userRefused: false, helperReturned: true)
    }
    await finishVolume(vol, cmd: cmd, result: result, openFinder: openFinder, extra: extra)
  }

  private func finishVolume(
    _ vol: NTFSVolume,
    cmd: String,
    result: Privileged.Outcome,
    openFinder: Bool,
    extra: [String] = []
  ) async {
    let shown = display(result.text)
    AppLog.volume.info(
      "\(cmd, privacy: .public) \(vol.id, privacy: .public) ok=\(result.ok, privacy: .public) name=\(vol.name, privacy: .private) mount=\(vol.mountPoint, privacy: .private)"
    )
    setMessage(shown, volumeId: vol.id)
    if result.ok {
      lastFailedCmd[vol.id] = nil
    } else {
      lastFailedCmd[vol.id] = cmd
    }
    refresh()
    if !result.ok,
       cmd == "unmount",
       !extra.contains("force"),
       UserFacingError.kind(from: result.text) == .diskBusy,
       confirmForceUnmount(vol, helperText: result.text) {
      await run("unmount", vol, extra: ["force"])
      return
    }
    if result.ok, cmd == "mount", openFinder {
      NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
    } else if !result.ok, cmd == "mount", VolumeHealth.looksLikeKextOrFSKitBlock(result.text) {
      alertKextIgnored(shown)
    }
    advanceMountAll(after: vol.id)
    if autoMountPumping == false { pumpAutoMount() }
  }

  private func confirmForceUnmount(_ vol: NTFSVolume, helperText: String = "") -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = ForceUnmountCopy.title(volumeName: vol.name)
    alert.informativeText = ForceUnmountCopy.body(
      volumeName: vol.name,
      occupiers: UserFacingError.occupierPids(from: helperText)
    )
    alert.addButton(withTitle: ForceUnmountCopy.cancelTitle)
    alert.addButton(withTitle: ForceUnmountCopy.forceTitle)
    makeCancelDefault(alert)
    return alert.runModal() == .alertSecondButtonReturn
  }

  /// Probe always records classify (including unknown). Mount/fix keep a known kind so "OK rw" does not wipe it.
  private func rememberHealthOutput(_ id: String, _ text: String, fromProbe: Bool = false) {
    lastHelperText[id] = text
    let kind = VolumeHealth.probeKind(from: text)
    if fromProbe || kind != .unknown {
      lastProbeKind[id] = kind
    }
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
    let confirmField = NSTextField()
    confirmField.placeholderString = disk.name
    confirmField.setAccessibilityLabel(L10n.t("format.confirmAccessibility"))
    let newCaption = NSTextField(labelWithString: L10n.t("format.newName"))
    let labelField = NSTextField()
    labelField.stringValue = disk.suggestedLabel
    labelField.setAccessibilityLabel(L10n.t("format.newNameAccessibility"))

    let stack = NSStackView(views: [currentCaption, confirmField, newCaption, labelField])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      confirmField.widthAnchor.constraint(equalToConstant: 320),
      labelField.widthAnchor.constraint(equalToConstant: 320),
    ])

    let box = NSView()
    box.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
      stack.topAnchor.constraint(equalTo: box.topAnchor),
      stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
    ])
    box.layoutSubtreeIfNeeded()
    let fitted = box.fittingSize
    box.frame = NSRect(
      x: 0,
      y: 0,
      width: max(fitted.width, 320),
      height: max(fitted.height, 96)
    )

    confirm = confirmField
    label = labelField
    view = box
  }
}
