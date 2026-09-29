import Foundation

public enum UserFacingError {
  public enum Kind: Equatable, Sendable {
    case canceled
    case helperInstallFailed
    case helperMissing
    case missingGoNfsv4
    case ntfs3gMissing
    case missingBinary
    case adminDenied
    case helperNeedsUpdate
    case diskBusy
    /// macOS refused a direct raw-device open (`Operation not permitted`) — usually missing
    /// Full Disk Access for the process doing the mounting / formatting.
    case rawDeviceDenied
    case other
  }

  public static func kind(from raw: String) -> Kind {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = t.lowercased()
    if lower.contains("user canceled")
      || t.contains("-128")
      || lower.contains("(-128)")
      || t.contains("-60006") {
      return .canceled
    }
    if t.contains("磁盘正被占用")
      || lower.contains("busy-occupiers:")
      || lower.contains("busy-lsof-failed:")
      || lower.contains("resource busy")
      || lower.contains("volume busy")
      || lower.contains("in use and cannot be ejected") {
      return .diskBusy
    }
    if lower.contains("operation not permitted") && t.contains("/dev/") {
      return .rawDeviceDenied
    }
    if lower.contains("password") && lower.contains("sudo") {
      return .helperNeedsUpdate
    }
    if looksLikeGoNfsv4(t, lower: lower) {
      return .missingGoNfsv4
    }
    if looksLikeNtfs3gMissing(t, lower: lower) {
      return .ntfs3gMissing
    }
    if looksLikeHelperMissing(t) {
      return .helperMissing
    }
    if looksLikeHelperInstall(t, lower: lower) {
      return .helperInstallFailed
    }
    if looksLikeMissingBinary(t, lower: lower) {
      return .missingBinary
    }
    if lower.contains("authorization denied")
      || lower.contains("authorization failed")
      || lower.contains("errauthorization")
      || t.contains("-60005")
      || t.contains("-60007") {
      return .adminDenied
    }
    if lower.contains("execution error") || lower.contains("osascript") || lower.contains("0:") {
      return .adminDenied
    }
    return .other
  }

  public static func message(from raw: String, logPath: String? = nil, locale: Locale? = nil) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return L10n.t("error.empty", locale: locale) }
    let kind = kind(from: t)
    let mapped: String
    switch kind {
    case .canceled:
      mapped = L10n.t("error.canceled", locale: locale)
    case .helperInstallFailed:
      mapped = L10n.t("error.helperInstallFailed", locale: locale)
    case .helperMissing:
      mapped = L10n.t("error.helperMissing", locale: locale)
    case .missingGoNfsv4:
      mapped = L10n.t("error.missingGoNfsv4", locale: locale)
    case .ntfs3gMissing:
      mapped = L10n.t("runtime.ntfs3gMissing", locale: locale)
    case .missingBinary:
      mapped = L10n.t("error.missingBinary", locale: locale)
    case .adminDenied:
      mapped = L10n.t("error.adminDenied", locale: locale)
    case .helperNeedsUpdate:
      mapped = L10n.t("error.helperNeedsUpdate", locale: locale)
    case .diskBusy:
      if let names = occupierNames(from: t) {
        mapped = L10n.format("error.diskBusyNamed", occupierSummary(names, locale: locale), locale: locale)
      } else if lsofProbeFailed(from: t) {
        mapped = L10n.t("error.diskBusy", locale: locale)
          + "\n" + L10n.t("error.diskBusyNeedFDA", locale: locale)
      } else {
        mapped = L10n.t("error.diskBusy", locale: locale)
      }
    case .rawDeviceDenied:
      mapped = L10n.t("error.rawDeviceDenied", locale: locale)
    case .other:
      if t.lowercased().contains("refused to eject") {
        mapped = L10n.t("eject.refuseSystem", locale: locale)
      } else if t.hasPrefix("error:") {
        mapped = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      } else if t.count > 180 {
        if let logPath {
          mapped = L10n.format("error.failedWithLog", logPath, locale: locale)
        } else {
          mapped = L10n.t("error.failedLog", locale: locale)
        }
      } else {
        mapped = t
      }
    }
    return withoutHanIfNeeded(mapped, kind: kind, logPath: logPath, locale: locale)
  }

  /// Helper stderr may be Chinese; never show Han in English/Japanese UI.
  private static func withoutHanIfNeeded(
    _ text: String,
    kind: Kind,
    logPath: String?,
    locale: Locale?
  ) -> String {
    guard !prefersChinese(locale), containsHan(text) else { return text }
    let kept = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map(String.init)
      .filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !containsHan(trimmed)
      }
    if !kept.isEmpty { return kept.joined(separator: "\n") }
    switch kind {
    case .diskBusy:
      return text
    case .other:
      if let logPath {
        return L10n.format("error.failedWithLog", logPath, locale: locale)
      }
      return L10n.t("error.failedLog", locale: locale)
    default:
      return text
    }
  }

  private static func prefersChinese(_ locale: Locale?) -> Bool {
    switch L10n.languageCode(for: locale) {
    case "zh-Hans", "zh-Hant": return true
    default: return false
    }
  }

  private static func containsHan(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
      (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
    }
  }

  /// First ~3 process names, then “and N more”.
  public static func occupierSummary(_ rawList: String, locale: Locale? = nil, limit: Int = 3) -> String {
    let parts = rawList.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    if parts.count <= limit { return parts.joined(separator: ", ") }
    let head = parts.prefix(limit).joined(separator: ", ")
    let more = parts.count - limit
    return head + ", " + L10n.format("error.occupiersMore", more, locale: locale)
  }

  static func lsofProbeFailed(from raw: String) -> Bool {
    raw.split(whereSeparator: \.isNewline).contains { line in
      line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("busy-lsof-failed:")
    }
  }

  /// Process names from helper `busy-occupiers:` or legacy Chinese busy text.
  public static func occupierNames(from raw: String) -> String? {
    for line in raw.split(whereSeparator: \.isNewline) {
      let t = line.trimmingCharacters(in: .whitespaces)
      let prefix = "busy-occupiers:"
      if t.lowercased().hasPrefix(prefix) {
        let names = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if !names.isEmpty { return names }
      }
    }
    return occupierNamesFromLegacyChinese(raw)
  }

  /// `Finder[412]` lines when present; otherwise process names.
  public static func occupierPids(from raw: String) -> String? {
    for line in raw.split(whereSeparator: \.isNewline) {
      let t = line.trimmingCharacters(in: .whitespaces)
      let prefix = "busy-pids:"
      if t.lowercased().hasPrefix(prefix) {
        let pids = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if !pids.isEmpty { return pids }
      }
    }
    return occupierNames(from: raw)
  }

  private static func occupierNamesFromLegacyChinese(_ raw: String) -> String? {
    let marker = "磁盘正被占用："
    guard let range = raw.range(of: marker) else { return nil }
    var rest = String(raw[range.upperBound...])
    if let nl = rest.firstIndex(of: "\n") {
      rest = String(rest[..<nl])
    }
    rest = rest.trimmingCharacters(in: .whitespaces)
    if rest.hasPrefix("请") { return nil }
    guard let dot = rest.firstIndex(of: "。") else { return nil }
    let names = String(rest[..<dot]).trimmingCharacters(in: .whitespaces)
    if names.isEmpty || names.hasPrefix("请") { return nil }
    return names
  }

  private static func looksLikeNtfs3gMissing(_ t: String, lower: String) -> Bool {
    if lower.contains("bundled-ntfs-3g-missing") { return true }
    if t.contains("找不到捆绑的 ntfs-3g") { return true }
    if t.contains("找不到內附") && lower.contains("ntfs-3g") { return true }
    if lower.contains("bundled ntfs-3g") && (lower.contains("not found") || lower.contains("missing")) {
      return true
    }
    return false
  }

  private static func looksLikeGoNfsv4(_ t: String, lower: String) -> Bool {
    lower.contains("go-nfsv4") && (
      t.contains("找不到")
        || lower.contains("no such file")
        || lower.contains("not found")
        || t.contains("(127)")
    )
  }

  private static func looksLikeHelperMissing(_ t: String) -> Bool {
    let lower = t.lowercased()
    return t.contains("未找到挂载助手")
      || t.contains("请点「安装挂载助手」")
      || t.contains("找不到挂载助手，请把应用装到")
      || lower.contains("mount helper not found")
      || t.contains("Install Mount Helper")
  }

  private static func looksLikeHelperInstall(_ t: String, lower: String) -> Bool {
    lower.contains("install-helper")
      || t.contains("应用包内缺少安装脚本")
      || t.contains("应用包内缺少特权守护进程")
      || t.contains("应用包内缺少挂载助手")
      || lower.contains("app package is missing")
  }

  private static func looksLikeMissingBinary(_ t: String, lower: String) -> Bool {
    t.contains("(127)")
      || lower.contains("no such file")
      || (lower.contains("not found") && !lower.contains("volume not found"))
  }
}
