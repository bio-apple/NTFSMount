import Foundation

/// Compact disk facts for the menu-bar submenu and window property grid.
/// BitLocker is a diskutil clue only — never Locked/Unlocked. Journal is probe/classify only.
public enum DiskStatus {
  public struct Row: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) {
      self.label = label
      self.value = value
    }

    public var line: String {
      L10n.format("diskStatus.line", label, value)
    }
  }

  public static func rows(
    volume: NTFSVolume,
    probeKind: VolumeHealth.ProbeKind? = nil,
    lastAdvice: VolumeHealth.MountAdvice? = nil,
    helperText: String = "",
    hasEncryptionHint: Bool? = nil,
    locale: Locale? = nil
  ) -> [Row] {
    let hint = hasEncryptionHint ?? volume.hasEncryptionHint
    return [
      Row(label: L10n.t("window.filesystem", locale: locale), value: "NTFS"),
      Row(
        label: L10n.t("diskStatus.mountMode", locale: locale),
        value: mountMode(volume, locale: locale)
      ),
      Row(label: L10n.t("window.capacity", locale: locale), value: volume.sizeLabel),
      Row(
        label: L10n.t("diskStatus.used", locale: locale),
        value: usedValue(volume, locale: locale)
      ),
      Row(
        label: L10n.t("diskStatus.encryption", locale: locale),
        value: encryptionValue(hasHint: hint, locale: locale)
      ),
      Row(
        label: L10n.t("diskStatus.journal", locale: locale),
        value: VolumeHealth.journalLabel(
          probeKind: probeKind,
          lastAdvice: lastAdvice,
          helperText: helperText,
          locale: locale
        )
      ),
    ]
  }

  public static func mountMode(_ vol: NTFSVolume, locale: Locale? = nil) -> String {
    if vol.isWritableFuse { return L10n.t("diskStatus.mountRW", locale: locale) }
    if vol.isReadOnlyMounted { return L10n.t("diskStatus.mountRO", locale: locale) }
    return L10n.t("status.unmounted", locale: locale)
  }

  public static func usedValue(_ vol: NTFSVolume, locale: Locale? = nil) -> String {
    if vol.hasUsage || vol.usedBytes > 0 {
      return ByteCountFormatter.string(fromByteCount: vol.usedBytes, countStyle: .file)
    }
    return L10n.t("window.usageAfterMount", locale: locale)
  }

  public static func encryptionValue(hasHint: Bool, locale: Locale? = nil) -> String {
    L10n.t(hasHint ? "diskStatus.encryptionHint" : "diskStatus.encryptionNone", locale: locale)
  }
}
