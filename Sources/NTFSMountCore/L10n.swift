import Foundation

/// In-app strings follow macOS preferred languages: en*, zh-Hans, zh-Hant, ja.
/// Unsupported system languages fall back to Simplified Chinese.
/// Missing keys fall back to English so English (and Japanese) UI never shows 简体中文.
public enum L10n {
  public static let fallbackLanguage = "zh-Hans"
  public static let catalogFallbackLanguage = "en"
  public static let supportedLanguages = ["en", "zh-Hans", "zh-Hant", "ja"]

  public static func languageCode(for locale: Locale? = nil) -> String {
    let ids: [String]
    if let locale {
      var list = [locale.identifier]
      if let lang = locale.language.languageCode?.identifier {
        list.append(lang)
      }
      if let lang = locale.language.languageCode?.identifier,
         let script = locale.language.script?.identifier {
        list.append("\(lang)-\(script)")
      }
      ids = list
    } else {
      ids = Locale.preferredLanguages
    }
    for id in ids {
      if let matched = matchLanguage(id) { return matched }
    }
    return fallbackLanguage
  }

  public static func t(_ key: String, locale: Locale? = nil) -> String {
    let lang = languageCode(for: locale)
    if let value = lookup(key, language: lang) { return value }
    if lang != catalogFallbackLanguage, let value = lookup(key, language: catalogFallbackLanguage) {
      return value
    }
    return key
  }

  public static func format(_ key: String, _ args: CVarArg..., locale: Locale? = nil) -> String {
    let pattern = t(key, locale: locale)
    let formatLocale = locale ?? Locale.autoupdatingCurrent
    return String(format: pattern, locale: formatLocale, arguments: args)
  }

  public static func matchLanguage(_ raw: String) -> String? {
    let s = raw.replacingOccurrences(of: "_", with: "-")
    let lower = s.lowercased()
    if lower.hasPrefix("en") { return "en" }
    if lower.hasPrefix("ja") { return "ja" }
    if lower.contains("hant")
      || lower.hasPrefix("zh-tw")
      || lower.hasPrefix("zh-hk")
      || lower.hasPrefix("zh-mo") {
      return "zh-Hant"
    }
    if lower.hasPrefix("zh") { return "zh-Hans" }
    return nil
  }

  private static func lookup(_ key: String, language: String) -> String? {
    for bundle in searchBundles() {
      if let url = bundle.url(
        forResource: "Localizable",
        withExtension: "strings",
        subdirectory: "\(language).lproj"
      ), let dict = NSDictionary(contentsOf: url) as? [String: String],
         let value = dict[key] {
        return value
      }
    }
    return nil
  }

  private static func searchBundles() -> [Bundle] {
    var bundles: [Bundle] = []
    var seen = Set<ObjectIdentifier>()
    func add(_ bundle: Bundle?) {
      guard let bundle else { return }
      let id = ObjectIdentifier(bundle)
      guard seen.insert(id).inserted else { return }
      bundles.append(bundle)
    }
    add(Bundle.main)
    #if SWIFT_PACKAGE
    add(Bundle.module)
    #endif
    let names = [
      "NTFSMount_NTFSMountCore.bundle",
      "NTFSMountCore_NTFSMountCore.bundle",
    ]
    var roots: [URL] = []
    if let url = Bundle.main.resourceURL { roots.append(url) }
    roots.append(Bundle.main.bundleURL)
    let token = Bundle(for: L10nBundleToken.self)
    if let url = token.resourceURL { roots.append(url) }
    roots.append(token.bundleURL)
    roots.append(token.bundleURL.deletingLastPathComponent())
    for root in roots {
      for name in names {
        add(Bundle(url: root.appendingPathComponent(name)))
      }
      add(Bundle(url: root))
    }
    add(token)
    return bundles
  }
}

private final class L10nBundleToken {}
