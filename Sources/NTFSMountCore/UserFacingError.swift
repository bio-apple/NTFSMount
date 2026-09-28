import Foundation

public enum UserFacingError {
  public enum Kind: Equatable, Sendable {
    case canceled
    case helperInstallFailed
    case helperMissing
    case missingGoNfsv4
    case missingBinary
    case adminDenied
    case helperNeedsUpdate
    case diskBusy
    case other
  }

  public static func kind(from raw: String) -> Kind {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = t.lowercased()
    if lower.contains("user canceled") || t.contains("-128") || lower.contains("(-128)") {
      return .canceled
    }
    if t.contains("磁盘正被占用")
      || lower.contains("resource busy")
      || lower.contains("volume busy")
      || lower.contains("in use and cannot be ejected") {
      return .diskBusy
    }
    if lower.contains("password") && lower.contains("sudo") {
      return .helperNeedsUpdate
    }
    if looksLikeGoNfsv4(t, lower: lower) {
      return .missingGoNfsv4
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
    if lower.contains("execution error") || lower.contains("osascript") || lower.contains("0:") {
      return .adminDenied
    }
    return .other
  }

  public static func message(from raw: String, logPath: String? = nil, locale: Locale? = nil) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return L10n.t("error.empty", locale: locale) }
    switch kind(from: t) {
    case .canceled:
      return L10n.t("error.canceled", locale: locale)
    case .helperInstallFailed:
      return L10n.t("error.helperInstallFailed", locale: locale)
    case .helperMissing:
      return L10n.t("error.helperMissing", locale: locale)
    case .missingGoNfsv4:
      return L10n.t("error.missingGoNfsv4", locale: locale)
    case .missingBinary:
      return L10n.t("error.missingBinary", locale: locale)
    case .adminDenied:
      return L10n.t("error.adminDenied", locale: locale)
    case .helperNeedsUpdate:
      return L10n.t("error.helperNeedsUpdate", locale: locale)
    case .diskBusy:
      if t.contains("磁盘正被占用") {
        if t.hasPrefix("error:") {
          return String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        return t
      }
      return L10n.t("error.diskBusy", locale: locale)
    case .other:
      if t.hasPrefix("error:") {
        return String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      }
      if t.count > 180 {
        if let logPath {
          return L10n.format("error.failedWithLog", logPath, locale: locale)
        }
        return L10n.t("error.failedLog", locale: locale)
      }
      return t
    }
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
