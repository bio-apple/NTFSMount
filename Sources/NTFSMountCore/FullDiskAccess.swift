import Foundation

/// Best-effort Full Disk Access guidance. FDA is a user grant in System Settings,
/// not an Info.plist prompt. The LaunchDaemon is a separate process and does not
/// inherit NTFSMount.app’s TCC.
public enum FullDiskAccess {
  /// Gated path used only for a readability probe. Never opened or parsed.
  public static let gatedPath = "/Library/Application Support/com.apple.TCC/TCC.db"
  public static let helperName = "ntfsmount-helperd"
  public static let helperInstallPath = "/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
  public static let diagnoseLineId = "full_disk_access"

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

  public static func diagnoseStatus(_ status: Status) -> DiagnoseStatus {
    switch status {
    case .granted: return .pass
    case .denied: return .conflict
    case .unknown: return .info
    }
  }
}
