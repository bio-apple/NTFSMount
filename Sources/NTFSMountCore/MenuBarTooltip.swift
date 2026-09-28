import Foundation

/// Hover text for the menu bar extra and each volume row.
public enum MenuBarTooltip {
  public static func accessMark(
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    locale: Locale? = nil
  ) -> String {
    if isWritableFuse { return L10n.t("tooltip.rw", locale: locale) }
    if isReadOnlyMounted { return L10n.t("tooltip.ro", locale: locale) }
    return L10n.t("tooltip.unmounted", locale: locale)
  }

  public static func card(_ vol: NTFSVolume, locale: Locale? = nil) -> String {
    let title = vol.mediaName.isEmpty ? vol.name : vol.mediaName
    let access = accessMark(
      isWritableFuse: vol.isWritableFuse,
      isReadOnlyMounted: vol.isReadOnlyMounted,
      locale: locale
    )
    let fs = L10n.format("tooltip.fsLine", access, locale: locale)
    return [title, fs, vol.id, vol.usageLine].joined(separator: "\n")
  }

  public static func extra(_ volumes: [NTFSVolume], locale: Locale? = nil) -> String {
    if volumes.isEmpty {
      return L10n.t("menu.noNTFS", locale: locale)
    }
    return volumes.map { card($0, locale: locale) }.joined(separator: "\n\n")
  }
}