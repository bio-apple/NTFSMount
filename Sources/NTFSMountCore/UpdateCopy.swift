import Foundation

/// 更新相关文案与 feed（feed 仅给维护者 / 公证后启用；未公证包不启动 Sparkle）。
public enum UpdateCopy {
  /// Appcast on the v1.0 release, not `/releases/latest/`.
  public static let feedURL =
    "https://github.com/bio-apple/NTFSMount/releases/download/v1.0/appcast.xml"

  public static var settingsGroup: String { L10n.t("update.settingsGroup") }
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
