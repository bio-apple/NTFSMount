import AppKit
import NTFSMountCore
import UniformTypeIdentifiers

/// Builds the diagnostic zip (script JSON when possible, otherwise in-process snapshot).
enum DiagnoseReportExporter {
  struct WriteError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  @MainActor
  static func beginExport(
    store: VolumeStore,
    snap: DiagnoseSnapshot?,
    report: String,
    sheetWindow: NSWindow?,
    onStart: @escaping () -> Void,
    onFinish: @escaping (Result<URL, Error>) -> Void
  ) {
    presentSavePanel(on: sheetWindow) { url in
      guard let url else { return }
      onStart()
      let volumes = store.volumes
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try writeZip(to: url, snap: snap, report: report, volumes: volumes)
          DispatchQueue.main.async { onFinish(.success(url)) }
        } catch {
          DispatchQueue.main.async { onFinish(.failure(error)) }
        }
      }
    }
  }

  @MainActor
  static func presentSavePanel(on window: NSWindow?, completion: @escaping (URL?) -> Void) {
    Privileged.prepareForAdminPrompt()
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowedContentTypes = [.zip]
    panel.nameFieldStringValue = DiagnoseExport.defaultFileName()
    panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    panel.message = L10n.t("diagnose.exportPrivacy")
    panel.title = L10n.t("diagnose.export")
    if let window, window.isVisible {
      panel.beginSheetModal(for: window) { response in
        completion(response == .OK ? panel.url : nil)
      }
    } else {
      completion(panel.runModal() == .OK ? panel.url : nil)
    }
  }

  static func writeZip(
    to url: URL,
    snap: DiagnoseSnapshot?,
    report: String,
    volumes: [NTFSVolume]
  ) throws {
    let payload = buildPayload(snap: snap, report: report, volumes: volumes)
    try writeZip(files: DiagnoseExport.files(from: payload), to: url)
  }

  static func writeZip(files: [DiagnoseExport.ArchiveFile], to url: URL) throws {
    let fm = FileManager.default
    let staging = fm.temporaryDirectory.appendingPathComponent(
      "NTFSMount-diagnose-\(UUID().uuidString)",
      isDirectory: true
    )
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    for file in files {
      guard DiagnoseExport.archiveFiles.contains(file.name),
            !file.name.contains("/") else {
        continue
      }
      guard let data = file.text.data(using: .utf8) else { continue }
      try data.write(to: staging.appendingPathComponent(file.name))
    }
    if fm.fileExists(atPath: url.path) {
      try fm.removeItem(at: url)
    }
    let cap = EnvironmentDiagnoseRunner.runCapture(
      "ditto",
      ["-c", "-k", "--norsrc", staging.path, url.path],
      timeout: 15
    )
    guard cap.status == 0, fm.fileExists(atPath: url.path) else {
      throw WriteError(message: L10n.t("diagnose.exportFailedSimple"))
    }
  }

  static func buildPayload(
    snap: DiagnoseSnapshot?,
    report: String,
    volumes: [NTFSVolume]
  ) -> DiagnoseExport.Payload {
    let scriptJSON = collectScriptJSON()
    let live = snap
      ?? scriptJSON.flatMap { EnvironmentDiagnose.parseJSON($0.data(using: .utf8) ?? Data()) }
      ?? EnvironmentDiagnoseRunner.liveSnapshot()
    let text: String
    if report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      text = EnvironmentDiagnose.reportText(from: EnvironmentDiagnose.lines(from: live))
    } else {
      text = report
    }
    return DiagnoseExport.Payload(
      diagnoseText: text,
      diagnoseJSON: scriptJSON ?? DiagnoseExport.snapshotJSON(live),
      versionsText: DiagnoseExport.versionsText(snap: live, bundledFile: bundledVersionsFile()),
      diskStatusText: DiagnoseExport.diskStatusText(
        volumes: volumes,
        diskutilList: collectDiskutilList()
      ),
      unifiedLogText: collectUnifiedLog(),
      readmeText: DiagnoseExport.readmeText()
    )
  }

  static func collectScriptJSON() -> String? {
    guard let script = EnvironmentDiagnoseRunner.bundledScriptPath() else { return nil }
    let cap = EnvironmentDiagnoseRunner.runCapture("bash", [script, "--json"], timeout: 25)
    guard cap.status == 0, let raw = String(data: cap.data, encoding: .utf8) else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("{") ? raw : nil
  }

  static func bundledVersionsFile() -> String? {
    let fm = FileManager.default
    let bundledVersions = Bundle.main.url(forResource: "versions", withExtension: "txt").map {
      $0.path(percentEncoded: false)
    }
    let candidates: [String?] = [
      bundledVersions,
      Bundle.main.bundlePath + "/Contents/Resources/versions.txt",
    ]
    for path in candidates.compactMap({ $0 }) where fm.isReadableFile(atPath: path) {
      return try? String(contentsOfFile: path, encoding: .utf8)
    }
    return nil
  }

  static func collectDiskutilList() -> String? {
    let cap = EnvironmentDiagnoseRunner.runCapture("diskutil", ["list"], timeout: 15)
    guard cap.status == 0 else { return nil }
    let text = String(data: cap.data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
  }

  static func collectUnifiedLog() -> String {
    let cap = EnvironmentDiagnoseRunner.runCapture(
      "log",
      DiagnoseExport.logShowArguments,
      timeout: 20,
      combineErr: true
    )
    let text = String(data: cap.data, encoding: .utf8) ?? ""
    if cap.status == 0 {
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return DiagnoseExport.logShowEmptyNote()
      }
      return text
    }
    return DiagnoseExport.logShowUnavailableNote(status: cap.status, detail: text)
  }
}
