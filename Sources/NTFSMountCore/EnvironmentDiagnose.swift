import Foundation

/// User-visible environment checks. Pass/fail mapping only; probes live in the app or diagnose script.
public enum DiagnoseStatus: String, Equatable, Sendable {
  case pass
  case fail
  case info
  case conflict

  public var mark: String {
    switch self {
    case .pass: return "✅"
    case .fail: return "❌"
    case .info: return "ℹ️"
    case .conflict: return "⚠️"
    }
  }
}

public struct DiagnoseLine: Equatable, Sendable, Identifiable {
  public let id: String
  public let status: DiagnoseStatus
  public let title: String

  public init(id: String, status: DiagnoseStatus, title: String) {
    self.id = id
    self.status = status
    self.title = title
  }

  public var displayLine: String { "\(status.mark) \(title)" }
}

public struct DiagnoseSnapshot: Equatable, Sendable {
  public var appleSilicon: Bool = false
  public var arch: String = "unknown"
  public var macosProduct: String = "macOS"
  public var macosVersion: String = "unknown"
  public var macosMajor: Int = 0
  public var bundledNtfs3g: Bool = false
  public var bundledNtfsfix: Bool = false
  public var bundledGoNfsv4: Bool = false
  public var goNfsv4Path: String = ""
  public var ntfs3gPath: String = ""
  public var ntfs3gVersion: String = ""
  public var ntfs3gRaw: String = ""
  /// nil = not probed; true/false from bundled `ntfs-3g --version`
  public var ntfs3gAllowed: Bool?
  public var pinnedFuseT: String = EnvironmentDiagnose.pinnedFuseT
  public var systemFuseTVersion: String = ""
  public var helperSocketExists: Bool = false
  public var helperPing: String = "absent"
  /// present | absent | brew_missing
  public var brewMacFuse: String = "brew_missing"
  /// present | absent | unavailable
  public var kextMacFuse: String = "unavailable"
  /// present | absent | unavailable
  public var sysextMacFuse: String = "unavailable"
  public var quarantine: Bool?
  /// notarized | accepted | rejected | unavailable
  public var spctl: String = "unavailable"
  /// granted | denied | unknown — readability probe in this process, not a TCC.db scrape
  public var fullDiskAccess: FullDiskAccess.Status = .unknown

  public init() {}
}

public enum EnvironmentDiagnose {
  public static let pinnedFuseT = "1.2.7"
  public static let minMacOSMajor = 13
  public static var reportHeader: String { L10n.t("diagnose.header") }

  public static func lines(from snap: DiagnoseSnapshot, locale: Locale? = nil) -> [DiagnoseLine] {
    var lines = [
      platformLine(snap, locale: locale),
      runtimeLine(snap, locale: locale),
      driverVersionLine(snap, locale: locale),
      fuseLine(snap, locale: locale),
      helperLine(snap, locale: locale),
    ]
    lines.append(fullDiskAccessLine(snap, locale: locale))
    if let conflict = conflictLine(snap, locale: locale) {
      lines.append(conflict)
    }
    lines.append(gatekeeperLine(snap, locale: locale))
    return lines
  }

  public static func reportText(from lines: [DiagnoseLine], locale: Locale? = nil) -> String {
    let body = lines.map(\.displayLine).joined(separator: "\n")
    return "\(L10n.t("diagnose.header", locale: locale))\n\n\(body)"
  }

  /// LaunchDaemon helper is missing or unreachable.
  public static func helperNeedsInstall(_ snap: DiagnoseSnapshot) -> Bool {
    !snap.helperSocketExists || snap.helperPing.hasPrefix("connect_failed")
  }

  /// Update copy only when a live helper (socket) exists but SHA/legacy is stale.
  /// Missing socket always uses the Install copy, even if leftover sudoers makes `helperNeedsUpdate` true.
  public static func helperOfferIsUpdate(socketExists: Bool, helperNeedsUpdate: Bool) -> Bool {
    socketExists && helperNeedsUpdate
  }

  /// Bundled ntfs-3g / ntfsfix / go-nfsv4 gap means a broken app copy, not a brew install.
  public static func bundledComponentsBroken(_ snap: DiagnoseSnapshot) -> Bool {
    !snap.bundledNtfs3g || !snap.bundledNtfsfix || !snap.bundledGoNfsv4
  }

  public static func parseJSON(_ data: Data) -> DiagnoseSnapshot? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return snapshot(from: root)
  }

  public static func snapshot(from root: [String: Any]) -> DiagnoseSnapshot {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = boolFlag(root["apple_silicon"])
    snap.arch = string(root["arch"], fallback: "unknown")
    snap.macosProduct = string(root["macos_product_name"], fallback: "macOS")
    snap.macosVersion = string(root["macos_version"], fallback: "unknown")
    snap.macosMajor = majorVersion(snap.macosVersion)
    let fuse = dict(root["fuse_t"])
    snap.bundledGoNfsv4 = boolFlag(fuse["bundled_present"])
    snap.goNfsv4Path = string(fuse["bundled_go_nfsv4"])
    let pin = string(fuse["pinned_version"])
    if !pin.isEmpty && pin != "unknown" { snap.pinnedFuseT = pin }
    snap.systemFuseTVersion = string(fuse["system_version"])
    let runtime = dict(root["runtime"])
    snap.bundledNtfs3g = boolFlag(runtime["ntfs_3g_present"])
    snap.bundledNtfsfix = boolFlag(runtime["ntfsfix_present"])
    snap.ntfs3gPath = string(runtime["ntfs_3g_path"])
    snap.ntfs3gVersion = string(runtime["ntfs_3g_version"])
    snap.ntfs3gRaw = string(runtime["ntfs_3g_raw"])
    if runtime["ntfs_3g_allowed"] != nil {
      snap.ntfs3gAllowed = boolFlag(runtime["ntfs_3g_allowed"])
    }
    let ntfs = dict(root["ntfs_3g"])
    if !ntfs.isEmpty {
      let path = string(ntfs["path"])
      if !path.isEmpty { snap.ntfs3gPath = path }
      let ver = string(ntfs["version"])
      if !ver.isEmpty { snap.ntfs3gVersion = ver }
      let raw = string(ntfs["raw"])
      if !raw.isEmpty { snap.ntfs3gRaw = raw }
      if ntfs["allowed"] != nil { snap.ntfs3gAllowed = boolFlag(ntfs["allowed"]) }
      if ntfs["present"] != nil { snap.bundledNtfs3g = boolFlag(ntfs["present"]) }
    }
    if runtime["go_nfsv4_present"] != nil {
      snap.bundledGoNfsv4 = boolFlag(runtime["go_nfsv4_present"]) || snap.bundledGoNfsv4
    }
    let goPath = string(runtime["go_nfsv4_path"])
    if !goPath.isEmpty { snap.goNfsv4Path = goPath }
    let runtimePin = string(runtime["pinned_fuse_t"])
    if !runtimePin.isEmpty && runtimePin != "unknown" { snap.pinnedFuseT = runtimePin }
    let helper = dict(root["helper"])
    snap.helperSocketExists = boolFlag(helper["socket_exists"])
    snap.helperPing = string(helper["ping"], fallback: "absent")
    let conflicts = dict(root["conflicts"])
    snap.brewMacFuse = string(conflicts["brew_macfuse"], fallback: "brew_missing")
    snap.kextMacFuse = string(conflicts["kext_macfuse"], fallback: "unavailable")
    snap.sysextMacFuse = string(conflicts["systemextensions_macfuse"], fallback: "unavailable")
    let gate = dict(root["gatekeeper"])
    if gate["quarantine"] != nil { snap.quarantine = boolFlag(gate["quarantine"]) }
    snap.spctl = string(gate["spctl"], fallback: "unavailable")
    let fda = dict(root["full_disk_access"])
    if !fda.isEmpty {
      let raw = string(fda["app"])
      snap.fullDiskAccess = FullDiskAccess.parseStatus(raw.isEmpty ? string(fda["process"]) : raw)
    } else {
      snap.fullDiskAccess = FullDiskAccess.parseStatus(string(root["full_disk_access"]))
    }
    return snap
  }

  // MARK: - lines

  static func platformLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    let osLabel = "\(snap.macosProduct) \(snap.macosVersion)"
    if !snap.appleSilicon {
      return DiagnoseLine(
        id: "platform",
        status: .fail,
        title: L10n.format("diagnose.notAppleSilicon", snap.arch, locale: locale)
      )
    }
    if snap.macosMajor > 0 && snap.macosMajor < minMacOSMajor {
      return DiagnoseLine(
        id: "platform",
        status: .fail,
        title: L10n.format("diagnose.needMacOS", osLabel, minMacOSMajor, locale: locale)
      )
    }
    return DiagnoseLine(
      id: "platform",
      status: .pass,
      title: L10n.format("diagnose.appleSiliconOK", osLabel, locale: locale)
    )
  }

  static func runtimeLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    var missing: [String] = []
    if !snap.bundledNtfs3g { missing.append("ntfs-3g") }
    if !snap.bundledNtfsfix { missing.append("ntfsfix") }
    if !snap.bundledGoNfsv4 { missing.append("go-nfsv4") }
    if missing.isEmpty {
      return DiagnoseLine(
        id: "runtime",
        status: .pass,
        title: L10n.t("diagnose.runtimeOK", locale: locale)
      )
    }
    return DiagnoseLine(
      id: "runtime",
      status: .fail,
      title: L10n.format("diagnose.runtimeMissing", missing.joined(separator: " / "), locale: locale)
    )
  }

  static func driverVersionLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    if !snap.bundledNtfs3g {
      return DiagnoseLine(
        id: Ntfs3gVersion.diagnoseLineId,
        status: .fail,
        title: Ntfs3gVersion.diagnoseMissing(locale: locale)
      )
    }
    let parsed = Ntfs3gVersion.parse(
      snap.ntfs3gRaw.isEmpty ? snap.ntfs3gVersion : snap.ntfs3gRaw
    )
    let ver: String = {
      if !snap.ntfs3gVersion.isEmpty && snap.ntfs3gVersion != "unknown" {
        return snap.ntfs3gVersion
      }
      return parsed.displayVersion
    }()
    let allowed = snap.ntfs3gAllowed ?? parsed.isAllowed
    if allowed {
      return DiagnoseLine(
        id: Ntfs3gVersion.diagnoseLineId,
        status: .pass,
        title: Ntfs3gVersion.diagnoseAllowed(ver, locale: locale)
      )
    }
    return DiagnoseLine(
      id: Ntfs3gVersion.diagnoseLineId,
      status: .conflict,
      title: Ntfs3gVersion.diagnoseUntested(ver, locale: locale)
    )
  }

  static func fuseLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    let pin = snap.pinnedFuseT.isEmpty ? pinnedFuseT : snap.pinnedFuseT
    if snap.bundledGoNfsv4 {
      var title = L10n.format("diagnose.fuseOK", pin, locale: locale)
      if !snap.goNfsv4Path.isEmpty {
        title += L10n.format("diagnose.fusePath", snap.goNfsv4Path, locale: locale)
      }
      let sys = snap.systemFuseTVersion
      if !sys.isEmpty && sys != "unknown" && sys != pin {
        title += L10n.format("diagnose.fuseSysUnused", sys, locale: locale)
      }
      return DiagnoseLine(id: "fuse_t", status: .pass, title: title)
    }
    return DiagnoseLine(
      id: "fuse_t",
      status: .fail,
      title: L10n.format("diagnose.fuseMissing", pin, locale: locale)
    )
  }

  static func helperLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    if !snap.helperSocketExists {
      return DiagnoseLine(
        id: "helper",
        status: .fail,
        title: L10n.t("diagnose.helperMissing", locale: locale)
      )
    }
    let ping = snap.helperPing
    if ping.contains("HELPER_VERSION=") || ping == "alive_caller_rejected" {
      let detail = ping == "alive_caller_rejected"
        ? L10n.t("diagnose.helperAliveRejected", locale: locale)
        : L10n.format("diagnose.helperAlive", ping, locale: locale)
      return DiagnoseLine(id: "helper", status: .pass, title: detail)
    }
    if ping.hasPrefix("connect_failed") {
      return DiagnoseLine(
        id: "helper",
        status: .fail,
        title: L10n.format("diagnose.helperConnectFailed", ping, locale: locale)
      )
    }
    return DiagnoseLine(
      id: "helper",
      status: .info,
      title: L10n.format("diagnose.helperPing", ping, locale: locale)
    )
  }

  static func fullDiskAccessLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    DiagnoseLine(
      id: FullDiskAccess.diagnoseLineId,
      status: FullDiskAccess.diagnoseStatus(snap.fullDiskAccess),
      title: FullDiskAccess.diagnoseTitle(snap.fullDiskAccess, locale: locale)
    )
  }

  static func conflictLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine? {
    let brew = snap.brewMacFuse == "present"
    let kext = snap.kextMacFuse == "present"
    let sysext = snap.sysextMacFuse == "present"
    guard brew || kext || sysext else { return nil }
    var bits: [String] = []
    if brew { bits.append("Homebrew macfuse") }
    if kext { bits.append("macFUSE kext") }
    if sysext { bits.append(L10n.t("diagnose.sysext", locale: locale)) }
    return DiagnoseLine(
      id: "macfuse_conflict",
      status: .conflict,
      title: L10n.format("diagnose.conflict", bits.joined(separator: " / "), locale: locale)
    )
  }

  static func gatekeeperLine(_ snap: DiagnoseSnapshot, locale: Locale? = nil) -> DiagnoseLine {
    if snap.quarantine == true {
      return DiagnoseLine(
        id: "gatekeeper",
        status: .fail,
        title: L10n.t("diagnose.quarantine", locale: locale)
      )
    }
    let spctl: String
    switch snap.spctl {
    case "notarized": spctl = L10n.t("diagnose.spctlNotarized", locale: locale)
    case "accepted": spctl = L10n.t("diagnose.spctlAccepted", locale: locale)
    case "rejected": spctl = L10n.t("diagnose.spctlRejected", locale: locale)
    default: spctl = L10n.t("diagnose.spctlUnchecked", locale: locale)
    }
    if snap.quarantine == false {
      return DiagnoseLine(
        id: "gatekeeper",
        status: .pass,
        title: L10n.format("diagnose.noQuarantine", spctl, locale: locale)
      )
    }
    return DiagnoseLine(
      id: "gatekeeper",
      status: .info,
      title: L10n.format("diagnose.gatekeeper", spctl, locale: locale)
    )
  }

  // MARK: - JSON helpers

  private static func dict(_ value: Any?) -> [String: Any] {
    value as? [String: Any] ?? [:]
  }

  private static func string(_ value: Any?, fallback: String = "") -> String {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return fallback
  }

  private static func boolFlag(_ value: Any?) -> Bool {
    if let boolVal = value as? Bool { return boolVal }
    if let n = value as? NSNumber { return n.boolValue }
    if let s = value as? String {
      return s == "true" || s == "1" || s.lowercased() == "yes"
    }
    return false
  }

  public static func majorVersion(_ version: String) -> Int {
    let head = version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first
    return head.flatMap { Int($0) } ?? 0
  }
}
