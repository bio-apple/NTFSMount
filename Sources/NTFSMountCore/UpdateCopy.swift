import Foundation

/// Sparkle 更新相关文案与 feed。
public enum UpdateCopy {
  /// GitHub pre-release v1.2.0 上的 appcast，不是 `/releases/latest/`。
  public static let feedURL =
    "https://github.com/bio-apple/NTFSMount/releases/download/v1.2.0/appcast.xml"

  public static var menuCheck: String { L10n.t("update.menuCheck") }
  public static var settingsGroup: String { L10n.t("update.settingsGroup") }
  public static var autoCheckToggle: String { L10n.t("update.autoCheck") }
  public static var checkNow: String { L10n.t("update.checkNow") }
  public static var autoCheckNote: String { L10n.t("update.autoCheckNote") }
  public static var settingsAboutLine: String { L10n.t("update.settingsAboutLine") }

  public static func aboutPrivacy(
    logPath: String,
    sourceURL: String,
    signingLine: String,
    locale: Locale? = nil
  ) -> String {
    L10n.format("update.aboutPrivacy", logPath, sourceURL, signingLine, locale: locale)
  }
}
