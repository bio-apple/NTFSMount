import Foundation

/// Marketing version from Info.plist (`CFBundleShortVersionString`). Never hardcode 1.0 in UI copy.
public enum AppVersion {
  public static func shortString(bundle: Bundle = .main) -> String {
    let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  public static func line(
    version: String? = nil,
    bundle: Bundle = .main,
    locale: Locale? = nil
  ) -> String {
    L10n.format("about.version", version ?? shortString(bundle: bundle), locale: locale)
  }

  public static func menuTitle(
    version: String? = nil,
    bundle: Bundle = .main,
    locale: Locale? = nil
  ) -> String {
    L10n.format("menu.about", version ?? shortString(bundle: bundle), locale: locale)
  }
}
