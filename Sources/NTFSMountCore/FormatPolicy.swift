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

public enum ForceUnmountCopy {
  public static var cancelTitle: String { FormatPolicy.cancelTitle }
  public static var forceTitle: String { L10n.t("forceUnmount.action") }

  public static func title(volumeName: String, locale: Locale? = nil) -> String {
    L10n.format("forceUnmount.title", volumeName, locale: locale)
  }

  public static func body(volumeName: String, occupiers: String? = nil, locale: Locale? = nil) -> String {
    let base = L10n.format("forceUnmount.body", volumeName, locale: locale)
    guard let occupiers, !occupiers.isEmpty else { return base }
    let summary = UserFacingError.occupierSummary(occupiers, locale: locale)
    return base + "\n" + L10n.format("forceUnmount.occupiers", summary, locale: locale)
  }

  public static func forceTitle(locale: Locale?) -> String {
    L10n.t("forceUnmount.action", locale: locale)
  }
}

public enum RepairMountCopy {
  public static var cancelTitle: String { FormatPolicy.cancelTitle }
  public static var actionTitle: String { L10n.t("repairEnv.action") }

  public static func title(locale: Locale? = nil) -> String {
    L10n.t("repairEnv.title", locale: locale)
  }

  public static func body(locale: Locale? = nil) -> String {
    L10n.t("repairEnv.body", locale: locale)
  }

  public static func actionTitle(locale: Locale?) -> String {
    L10n.t("repairEnv.action", locale: locale)
  }

  public static func parseCounts(_ text: String) -> (unmounted: Int, killed: Int, busy: Int)? {
    guard let line = text.split(whereSeparator: \.isNewline)
      .map(String.init)
      .first(where: { $0.hasPrefix("ok repair-env ") })
    else { return nil }
    func value(_ key: String) -> Int? {
      let needle = "\(key)="
      guard let range = line.range(of: needle) else { return nil }
      let digits = line[range.upperBound...].prefix(while: \.isNumber)
      return Int(digits)
    }
    guard let unmounted = value("unmounted"),
          let killed = value("killed"),
          let busy = value("busy")
    else { return nil }
    return (unmounted, killed, busy)
  }

  public static func summary(unmounted: Int, killed: Int, busy: Int, locale: Locale? = nil) -> String {
    if unmounted == 0, killed == 0, busy == 0 {
      return L10n.t("repairEnv.summaryNone", locale: locale)
    }
    if busy > 0 {
      return L10n.format("repairEnv.summaryBusy", unmounted, killed, busy, locale: locale)
    }
    return L10n.format("repairEnv.summary", unmounted, killed, locale: locale)
  }

  /// User-visible repair result. Never returns helper Chinese; counts come from `ok repair-env`.
  public static func userMessage(
    helperText: String,
    helperOK: Bool,
    helperRestarted: Bool,
    locale: Locale? = nil
  ) -> String {
    var parts: [String] = []
    if let counts = parseCounts(helperText) {
      parts.append(
        summary(unmounted: counts.unmounted, killed: counts.killed, busy: counts.busy, locale: locale)
      )
    } else if helperOK {
      parts.append(L10n.t("repairEnv.summaryNone", locale: locale))
    } else {
      let kind = UserFacingError.kind(from: helperText)
      switch kind {
      case .other, .diskBusy:
        parts.append(L10n.t("repairEnv.failed", locale: locale))
      default:
        parts.append(UserFacingError.message(from: helperText, locale: locale))
      }
    }
    if helperRestarted {
      parts.append(L10n.t("repairEnv.helperRestarted", locale: locale))
    }
    return parts.joined(separator: "\n")
  }
}
