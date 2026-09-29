import Foundation

/// Best-effort Full Disk Access guidance. FDA is a user grant in System Settings,
/// not an Info.plist prompt. The LaunchDaemon is a separate process and does not
/// inherit NTFSMount.app’s TCC.
public enum FullDiskAccess {
  /// Gated path used only for a readability probe. Never opened or parsed.
  public static let gatedPath = "/Library/Application Support/com.apple.TCC/TCC.db"
  public static let helperName = "ntfsmount-helperd"
  /// Where launchd actually starts `ntfsmount-helperd`, most likely first. TCC keys Full Disk
  /// Access by the *running* binary, so the grant must name one of these, not NTFSMount.app.
  public static let helperInstallPaths = [
    "/Library/Application Support/NTFSMount/ntfsmount-helperd",
    "/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd",
  ]
  public static let helperInstallPath = helperInstallPaths[0]
  public static let diagnoseLineId = "full_disk_access"

  /// The daemon launchd is running (or would run) from. Prefer a sealed copy; fall back to the
  /// app bundle, which is what an SMAppService (notarized) install uses.
  public static func runningHelperPath(
    appBundlePath: String = Bundle.main.bundlePath,
    exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> String {
    let bundled = appBundlePath + "/Contents/MacOS/" + helperName
    return (helperInstallPaths + [bundled]).first(where: exists) ?? helperInstallPath
  }

  public enum Status: String, Equatable, Sendable {
    case granted
    case denied
    case unknown
  }

  /// Readability of `gatedPath` in this process. Not a TCC.db scrape.
  public static func probe(
    pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
    pathIsReadable: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
  ) -> Status {
    guard pathExists(gatedPath) else { return .unknown }
    return pathIsReadable(gatedPath) ? .granted : .denied
  }

  public static func parseStatus(_ raw: String?) -> Status {
    switch (raw ?? "").lowercased() {
    case Status.granted.rawValue: return .granted
    case Status.denied.rawValue: return .denied
    default: return .unknown
    }
  }

  /// Sequoia/Tahoe first, then the long-standing Privacy_AllFiles URL.
  public static func settingsURLs(macosMajor: Int) -> [URL] {
    var specs: [String] = []
    if macosMajor >= 15 {
      specs.append(
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
      )
      specs.append(
        "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_AllFiles"
      )
    }
    specs.append("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    return specs.compactMap { URL(string: $0) }
  }

  public static func diagnoseTitle(_ status: Status, locale: Locale? = nil) -> String {
    switch status {
    case .granted: return L10n.t("diagnose.fdaGranted", locale: locale)
    case .denied: return L10n.t("diagnose.fdaDenied", locale: locale)
    case .unknown: return L10n.t("diagnose.fdaUnknown", locale: locale)
    }
  }

  /// One-time prompt until the user has been asked. Granted access never prompts.
  public static func shouldPrompt(status: Status, alreadyPrompted: Bool) -> Bool {
    status != .granted && !alreadyPrompted
  }

  public static func diagnoseStatus(_ status: Status) -> DiagnoseStatus {
    switch status {
    case .granted: return .pass
    case .denied: return .conflict
    case .unknown: return .info
    }
  }
}
