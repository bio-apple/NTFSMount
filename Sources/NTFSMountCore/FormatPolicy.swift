import Foundation

public enum FormatPolicy {
  public static var cancelTitle: String { L10n.t("format.cancel") }
  public static var formatTitle: String { L10n.t("format.action") }

  public static func cancelTitle(locale: Locale?) -> String {
    L10n.t("format.cancel", locale: locale)
  }

  public static func confirms(typed: String, currentName: String) -> Bool {
    typed == currentName
  }

  public static func identityLines(
    sizeLabel: String,
    deviceId: String,
    serial: String,
    fsHint: String,
    mediaName: String,
    locale: Locale? = nil
  ) -> String {
    var lines = [
      L10n.format("format.identitySize", sizeLabel, locale: locale),
      L10n.format("format.identityDevice", deviceId, locale: locale),
    ]
    if !mediaName.isEmpty {
      lines.append(L10n.format("format.identityMedia", mediaName, locale: locale))
    }
    let serialLine = serial.isEmpty ? L10n.t("format.unknown", locale: locale) : serial
    lines.append(L10n.format("format.identitySerial", serialLine, locale: locale))
    if !fsHint.isEmpty {
      lines.append(L10n.format("format.identityFS", fsHint, locale: locale))
    }
    return lines.joined(separator: "\n")
  }

  public static func finalWarning(
    name: String,
    sizeLabel: String,
    deviceId: String,
    serial: String,
    locale: Locale? = nil
  ) -> String {
    let serialLine = serial.isEmpty ? L10n.t("format.unknown", locale: locale) : serial
    return L10n.format("format.finalWarning", name, sizeLabel, deviceId, serialLine, locale: locale)
  }

  public static func wholeDiskId(_ id: String) -> String {
    if let range = id.range(of: #"s\d"#, options: .regularExpression) {
      return String(id[..<range.lowerBound])
    }
    return id
  }

  public static func sanitizeLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed
      .replacingOccurrences(of: "/", with: "")
      .replacingOccurrences(of: "\"", with: "")
      .replacingOccurrences(of: "\\", with: "")
    let limited = String(cleaned.prefix(32))
    return limited.isEmpty ? "NTFS" : limited
  }
}

public func wholeDiskId(_ id: String) -> String {
  FormatPolicy.wholeDiskId(id)
}
