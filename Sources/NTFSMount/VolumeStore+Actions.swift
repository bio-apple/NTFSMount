import AppKit
import NTFSMountCore
import ServiceManagement
import os

@MainActor
extension VolumeStore {
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
    if !confirmDriverIfNeeded(volumeId: vol.id) {
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
    await removeThen("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) async {
    if vol.isInternal {
      setMessage(L10n.t("eject.refuseInternal"), volumeId: vol.id)
      return
    }
    skippedUnmount.insert(vol.id)
    await removeThen("eject", vol)
  }

  private func removeThen(_ cmd: String, _ vol: NTFSVolume, extra: [String] = []) async {
    guard await cleanMacJunkIfNeeded(vol, command: cmd, isForce: extra.contains("force")) else {
      return
    }
    await run(cmd, vol, extra: extra)
  }

  /// Returns false when the user cancels after a clean failure.
  private func cleanMacJunkIfNeeded(_ vol: NTFSVolume, command: String, isForce: Bool) async -> Bool {
    guard MacJunkCleanup.shouldRun(
      enabled: cleanMacJunkBeforeEject,
      isInternal: vol.isInternal,
      isWritableFuse: vol.isWritableFuse,
      mountPoint: vol.mountPoint,
      command: command,
      isForce: isForce
    ) else { return true }
    busyId = vol.id
    setMessage(L10n.t("cleanJunk.working"), volumeId: vol.id)
    let root = vol.mountPoint
    let outcome = await withCheckedContinuation { (cont: CheckedContinuation<MacJunkCleanup.Outcome, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        cont.resume(returning: MacJunkCleanup.clean(at: root))
      }
    }
    AppLog.append(
      "clean-junk \(vol.id) removed=\(outcome.removedCount) failed=\(outcome.failedPaths.count)"
    )
    if outcome.failedPaths.isEmpty {
      // Do not overlay helper stderr. Eject/unmount busy text includes busy-occupiers.
      return true
    }
    busyId = nil
    setMessage(MacJunkCleanup.Copy.failedBody(volumeName: vol.name), volumeId: vol.id)
    if confirmContinueWithoutClean(vol) {
      return true
    }
    setMessage(L10n.t("error.canceled"), volumeId: vol.id)
    return false
  }

  private func confirmContinueWithoutClean(_ vol: NTFSVolume) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = MacJunkCleanup.Copy.failedTitle()
    alert.informativeText = MacJunkCleanup.Copy.failedBody(volumeName: vol.name)
    alert.addButton(withTitle: MacJunkCleanup.Copy.continueTitle())
    alert.addButton(withTitle: FormatPolicy.cancelTitle)
    makeSafeDefault(alert)
    return alert.runModal() == .alertFirstButtonReturn
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

  func format(_ disk: FormatDisk, label: String) async {
    busyId = disk.id
    setMessage("")
    let result = await Privileged.run("format", disk.id, extra: [label])
    busyId = nil
    let shown = display(result.text)
    // 失败原文必须留痕：菜单底部那一行很容易被忽略，诊断要能拿到原文。
    AppLog.append("format \(disk.id) ok=\(result.ok) label=\(label): \(result.text)")
    setMessage(shown)
    if !result.ok { alertFormatFailed(shown) }
    refresh()
    if result.ok, let vol = volumes.first(where: { wholeDiskId($0.id) == disk.id }) {
      await mount(vol)
    }
  }

  private func alertFormatFailed(_ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.t("alert.formatFailed")
    alert.informativeText = detail
    alert.addButton(withTitle: L10n.t("ok.gotIt"))
    alert.runModal()
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

  func toggleCleanMacJunkBeforeEject() {
    cleanMacJunkBeforeEject.toggle()
    UserDefaults.standard.set(
      cleanMacJunkBeforeEject,
      forKey: AppIdentity.Defaults.cleanMacJunkBeforeEject
    )
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
      userOptedOff: UserDefaults.standard.bool(forKey: AppIdentity.Defaults.autoMountUserOff)
    ) else { return }
    AppIdentity.markWritableAccepted()
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
    // Helper stderr is the source of truth (busy-occupiers / busy-pids). Do not replace it.
    let shown = display(result.text)
    AppLog.volume.info("\(cmd, privacy: .public) \(vol.id, privacy: .public) ok=\(result.ok, privacy: .public)")
    AppLog.volume.info("name=\(vol.name, privacy: .private) mp=\(vol.mountPoint, privacy: .private)")
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
    if !result.ok,
       cmd == "eject",
       UserFacingError.kind(from: result.text) == .diskBusy {
      alertDiskBusy(shown)
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
