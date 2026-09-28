import Foundation

/// 捆绑 ntfs-3g 版本校验。允许列表与 `runtime/versions.txt`、`scripts/ntfs3g-version.sh` 一致。
/// 未知 / 更旧 / 更新：警告风险，默认不硬拦挂载。只查 helper 执行的捆绑二进制，不查 PATH。
public enum Ntfs3gVersion {
  /// 与 runtime/versions.txt 的 `ntfs-3g` 钉死版本一致。
  public static let pinned = "2026.7.7"
  public static let allowListHuman = "2026.7.7、2026.8.x"
  public static let diagnoseLineId = "ntfs_3g_version"

  public enum Status: Equatable, Sendable {
    case allowed
    case untested
    case missing
  }

  public struct Parsed: Equatable, Sendable {
    public let raw: String
    public let year: Int?
    public let month: Int?
    public let patch: Int?

    public init(raw: String, year: Int?, month: Int?, patch: Int?) {
      self.raw = raw
      self.year = year
      self.month = month
      self.patch = patch
    }

    public var displayVersion: String {
      guard let year, let month, let patch else { return "unknown" }
      return "\(year).\(month).\(patch)"
    }

    public var isAllowed: Bool {
      Ntfs3gVersion.isAllowed(year: year, month: month, patch: patch)
    }

    public var status: Status {
      if year == nil {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .missing : .untested
      }
      return isAllowed ? .allowed : .untested
    }
  }

  public static func isAllowed(year: Int?, month: Int?, patch: Int?) -> Bool {
    guard let year, let month, let patch else { return false }
    if year == 2026 && month == 7 && patch == 7 { return true }
    if year == 2026 && month == 8 && (0...99).contains(patch) { return true }
    return false
  }

  public static func parse(_ output: String) -> Parsed {
    let text = output.replacingOccurrences(of: "\r", with: " ")
    if let triple = firstTriple(in: text, preferNtfs3gPrefix: true)
      ?? firstTriple(in: text, preferNtfs3gPrefix: false)
    {
      return Parsed(raw: output, year: triple.0, month: triple.1, patch: triple.2)
    }
    return Parsed(raw: output, year: nil, month: nil, patch: nil)
  }

  // MARK: - 文案

  public static var diagnoseMissing: String { L10n.t("ntfs3g.diagnoseMissing") }
  public static var mountWarningTitle: String { L10n.t("ntfs3g.mountWarningTitle") }
  public static var continueTitle: String { L10n.t("ntfs3g.continue") }
  public static var cancelTitle: String { L10n.t("cancel") }
  public static var settingsChecking: String { L10n.t("ntfs3g.settingsChecking") }
  public static var allowListCaption: String { L10n.t("ntfs3g.allowListCaption") }
  public static var settingsGroupTitle: String { L10n.t("ntfs3g.settingsGroup") }

  public static func diagnoseMissing(locale: Locale?) -> String {
    L10n.t("ntfs3g.diagnoseMissing", locale: locale)
  }

  public static func diagnoseAllowed(_ version: String, locale: Locale? = nil) -> String {
    L10n.format("ntfs3g.diagnoseAllowed", version, allowListHuman, locale: locale)
  }

  public static func diagnoseUntested(_ version: String, locale: Locale? = nil) -> String {
    L10n.format("ntfs3g.diagnoseUntested", version, allowListHuman, locale: locale)
  }

  public static func settingsLine(_ parsed: Parsed, locale: Locale? = nil) -> String {
    switch parsed.status {
    case .missing:
      return L10n.t("ntfs3g.diagnoseMissing", locale: locale)
    case .allowed:
      return L10n.format("ntfs3g.settingsAllowed", parsed.displayVersion, allowListHuman, locale: locale)
    case .untested:
      return L10n.format("ntfs3g.settingsUntested", parsed.displayVersion, allowListHuman, locale: locale)
    }
  }

  public static func mountWarningBody(_ parsed: Parsed, locale: Locale? = nil) -> String {
    L10n.format("ntfs3g.mountWarningBody", parsed.displayVersion, allowListHuman, locale: locale)
  }

  // MARK: - parse

  private static let prefixed = try! NSRegularExpression(
    pattern: #"ntfs-3g[[:space:]]+v?(\d{4})\.(\d{1,2})\.(\d{1,3})"#,
    options: [.caseInsensitive]
  )
  private static let anyTriple = try! NSRegularExpression(
    pattern: #"(\d{4})\.(\d{1,2})\.(\d{1,3})"#,
    options: []
  )

  private static func firstTriple(in text: String, preferNtfs3gPrefix: Bool) -> (Int, Int, Int)? {
    let re = preferNtfs3gPrefix ? prefixed : anyTriple
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = re.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 4
    else { return nil }
    guard let year = Int(ns.substring(with: match.range(at: 1))),
          let month = Int(ns.substring(with: match.range(at: 2))),
          let patch = Int(ns.substring(with: match.range(at: 3)))
    else { return nil }
    return (year, month, patch)
  }
}
