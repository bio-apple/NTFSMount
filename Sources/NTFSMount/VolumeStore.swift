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
  @Published var showDock: Bool = AppIdentity.bool(forKey: AppIdentity.Defaults.showDock, default: true)
  @Published var cleanMacJunkBeforeEject: Bool = AppIdentity.bool(
    forKey: AppIdentity.Defaults.cleanMacJunkBeforeEject,
    default: true
  )
  @Published var openSettings = false
  /// First open: diagnose then repair. Other menu actions stay disabled until the result alert closes.
  @Published var firstLaunchSetupBusy = false
  /// Indeterminate bar while the first open installs the mount helper.
  @Published var showHelperInstallProgress = false
  @Published var driverVersionLine: String = Ntfs3gVersion.settingsChecking
  @Published var driverVersionUntested = false

  private var timer: Timer?
  private var diskWatch = DiskWatch()
  var skippedUnmount = Set<String>()
  var autoMountAttempted = Set<String>()
  var autoMountQueue: [String] = []
  var autoMountPumping = false
  var mountAllQueue: [String] = []
  var mountAllPumping = false
  var lastAdvice: [String: VolumeHealth.MountAdvice] = [:]
  var lastHelperText: [String: String] = [:]
  var lastProbeKind: [String: VolumeHealth.ProbeKind] = [:]
  private var volumeMessages: [String: String] = [:]
  var lastFailedCmd: [String: String] = [:]
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
      self?.startSessionAfterLegal()
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

  /// After legal consent: first open diagnoses then repairs. Later opens only install a missing helper.
  func startSessionAfterLegal() {
    guard LegalGate.hasAcceptedLegal else { return }
    let finished = UserDefaults.standard.bool(forKey: AppIdentity.Defaults.didFinishFirstLaunchSetup)
    if AutoMountPolicy.shouldRunFirstLaunchSetup(alreadyFinished: finished, legalAccepted: true) {
      Task { [weak self] in
        await self?.runFirstLaunchSetup()
        self?.checkGitHubReleaseUpdateIfNeeded()
      }
      return
    }
    installHelperOnFirstLaunch()
    enableAutoMountDefault()
    promptFullDiskAccessIfNeeded()
    checkGitHubReleaseUpdateIfNeeded()
  }

  /// Missing Full Disk Access is a warning, not a mount failure. Ask once, then open Settings.
  func promptFullDiskAccessIfNeeded() {
    let status = FullDiskAccess.probe()
    let hash = AppCodeIdentity.cdhash()
    let promptedHash = UserDefaults.standard.string(forKey: AppIdentity.Defaults.didPromptFullDiskAccessHash) ?? ""
    let prompted = UserDefaults.standard.bool(forKey: AppIdentity.Defaults.didPromptFullDiskAccess)
      && !hash.isEmpty
      && promptedHash == hash
    guard FullDiskAccess.shouldPrompt(status: status, alreadyPrompted: prompted) else { return }
    UserDefaults.standard.set(true, forKey: AppIdentity.Defaults.didPromptFullDiskAccess)
    if !hash.isEmpty {
      UserDefaults.standard.set(hash, forKey: AppIdentity.Defaults.didPromptFullDiskAccessHash)
    }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("settings.fda")
    alert.informativeText = FullDiskAccess.diagnoseTitle(status)
    alert.addButton(withTitle: L10n.t("fda.open"))
    alert.addButton(withTitle: L10n.t("later"))
    if alert.runModal() == .alertFirstButtonReturn {
      FullDiskAccessSettings.openPane()
    }
  }

  /// Diagnose, install the helper if needed, repair, then show the result. Menu stays locked.
  func runFirstLaunchSetup() async {
    firstLaunchSetupBusy = true
    setMessage(L10n.t("diagnose.checking"))
    await EnvironmentDiagnosePresenter.presentAndWait(store: self)
    if AutoMountPolicy.shouldAutoInstallHelper(daemonReady: Privileged.daemonReady) {
      _ = await installHelperOnOpen()
    }
    guard helperInstalled else {
      let text = L10n.t("error.helperMissing")
      setMessage(text)
      presentRepairFinished(Privileged.Outcome(ok: false, text: text))
      firstLaunchSetupBusy = false
      EnvironmentDiagnosePresenter.refreshActions()
      promptFullDiskAccessIfNeeded()
      return
    }
    let outcome = await repairMountEnvironment()
    UserDefaults.standard.set(true, forKey: AppIdentity.Defaults.didFinishFirstLaunchSetup)
    presentRepairFinished(outcome)
    firstLaunchSetupBusy = false
    EnvironmentDiagnosePresenter.refreshActions()
    enableAutoMountDefault()
    promptFullDiskAccessIfNeeded()
  }

  func presentRepairFinished(_ outcome: Privileged.Outcome) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = outcome.ok ? .informational : .warning
    alert.messageText = outcome.ok ? L10n.t("repairEnv.doneTitle") : L10n.t("repairEnv.failed")
    let detail = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !detail.isEmpty, detail != alert.messageText {
      alert.informativeText = detail
    }
    alert.addButton(withTitle: L10n.t("ok.gotIt"))
    alert.runModal()
  }

  /// After the legal dialog: install the mount helper when its socket is missing.
  func installHelperOnFirstLaunch() {
    guard LegalGate.hasAcceptedLegal else { return }
    guard AutoMountPolicy.shouldAutoInstallHelper(daemonReady: Privileged.daemonReady) else { return }
    Task { _ = await installHelperOnOpen() }
  }

  /// First open: bring the app window forward and keep a progress bar up until install returns.
  func installHelperOnOpen() async -> Privileged.Outcome {
    showMainWindow()
    showHelperInstallProgress = true
    let outcome = await installHelper()
    showHelperInstallProgress = false
    return outcome
  }

  /// Online: compare CFBundleShortVersionString to GitHub Latest. Offline / failure: stay quiet.
  /// Does not install the mount helper; Settings / menu still can.
  func checkGitHubReleaseUpdateIfNeeded() {
    let current = AppVersion.shortString()
    guard !current.isEmpty else { return }
    let skipped = UserDefaults.standard.string(forKey: AppIdentity.Defaults.skippedReleaseVersion)
    Task { [weak self] in
      guard let remote = await GitHubReleaseChecker.fetchLatestVersion() else { return }
      guard GitHubReleaseUpdate.shouldPrompt(current: current, remote: remote, skipped: skipped)
      else { return }
      await MainActor.run { self?.presentAppUpdateOffer(remoteVersion: remote) }
    }
  }

  func presentAppUpdateOffer(remoteVersion: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = L10n.t("alert.appUpdateTitle")
    alert.informativeText = L10n.format("alert.appUpdateBody", remoteVersion)
    alert.addButton(withTitle: L10n.t("alert.update"))
    alert.addButton(withTitle: L10n.t("later"))
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(GitHubReleaseUpdate.latestPackageURL)
    } else {
      UserDefaults.standard.set(
        GitHubReleaseUpdate.normalizeVersion(remoteVersion),
        forKey: AppIdentity.Defaults.skippedReleaseVersion
      )
    }
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
        isReadOnlyMounted: vol.isReadOnlyMounted,
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

  func alertDiskBusy(_ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    let parts = detail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    alert.messageText = String(parts[0])
    if parts.count > 1 {
      alert.informativeText = String(parts[1])
    }
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

  func confirmDriverIfNeeded(volumeId: String? = nil) -> Bool {
    let parsed = cachedNtfs3g ?? EnvironmentDiagnoseRunner.probeNtfs3g()
    applyDriverVersion(parsed)
    if parsed.status == .missing {
      setMessage(L10n.t("runtime.ntfs3gMissing"), volumeId: volumeId)
      return false
    }
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

  func makeCancelDefault(_ alert: NSAlert) {
    applyKeyEquivalents(AlertDefaultPolicy.cancelDefault, to: alert)
  }

  func makeSafeDefault(_ alert: NSAlert) {
    applyKeyEquivalents(AlertDefaultPolicy.safeDefault, to: alert)
  }

  func applyKeyEquivalents(_ policy: AlertDefaultPolicy, to alert: NSAlert) {
    let count = alert.buttons.count
    for (i, button) in alert.buttons.enumerated() {
      button.keyEquivalent = policy.keyEquivalent(at: i, buttonCount: count)
    }
  }

  func rememberHealthOutput(_ id: String, _ text: String, fromProbe: Bool = false) {
    lastHelperText[id] = text
    let kind = VolumeHealth.probeKind(from: text)
    if fromProbe || kind != .unknown {
      lastProbeKind[id] = kind
    }
  }

  func setMessage(_ text: String, volumeId: String? = nil) {
    message = text
    messageVolumeId = volumeId
    if let volumeId {
      volumeMessages[volumeId] = text
    }
  }

  func display(_ raw: String) -> String {
    if raw.count > 180 { AppLog.append("raw: \(raw)") }
    return UserFacingError.message(from: raw, logPath: AppLog.url.path)
  }
}

