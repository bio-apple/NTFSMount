import Foundation

/// 首次启动确认框文案。回车是「同意并继续」；不同意请点「退出」或按 Esc。
/// `copyVersion` 变更时会再次弹出。Gatekeeper / xattr 不放进本框。
public enum OnboardingCopy {
  public static let copyVersion = 6

  public static var quitTitle: String { quitTitle(locale: nil) }
  public static var agreeTitle: String { agreeTitle(locale: nil) }
  public static var messageTitle: String { messageTitle(locale: nil) }
  public static var gatekeeperTitle: String { gatekeeperTitle(locale: nil) }
  public static var gatekeeperBody: String { gatekeeperBody(locale: nil) }

  public static func quitTitle(locale: Locale?) -> String {
    L10n.t("onboarding.quit", locale: locale)
  }

  public static func agreeTitle(locale: Locale?) -> String {
    L10n.t("onboarding.agree", locale: locale)
  }

  public static func messageTitle(locale: Locale?) -> String {
    L10n.t("onboarding.title", locale: locale)
  }

  public static func gatekeeperTitle(locale: Locale?) -> String {
    L10n.t("onboarding.gatekeeperTitle", locale: locale)
  }

  public static func gatekeeperBody(locale: Locale?) -> String {
    L10n.t("onboarding.gatekeeperBody", locale: locale)
  }

  public static func body(notarized: Bool, locale: Locale? = nil) -> String {
    _ = notarized
    return L10n.t("onboarding.body", locale: locale)
  }
}
