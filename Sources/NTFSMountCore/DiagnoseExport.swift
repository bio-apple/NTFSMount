import Foundation

/// Documented layout of the in-app diagnostic zip. Collection of live probes stays in the app.
public enum DiagnoseExport {
  public static let archiveFiles = [
    "README.txt",
    "diagnose.txt",
    "diagnose.json",
    "versions.txt",
    "disk-status.txt",
    "unified-log.txt",
  ]

  public static let logShowLast = "1h"
  public static let logShowPredicate =
    #"subsystem CONTAINS "bioapple" OR process CONTAINS "NTFSMount" OR process CONTAINS "ntfsmount""#

  public static var logShowArguments: [String] {
    ["show", "--last", logShowLast, "--predicate", logShowPredicate]
  }

  public struct Payload: Equatable, Sendable {
    public var diagnoseText: String
    public var diagnoseJSON: String
    public var versionsText: String
    public var diskStatusText: String
    public var unifiedLogText: String
    public var readmeText: String

    public init(
      diagnoseText: String,
      diagnoseJSON: String,
      versionsText: String,
      diskStatusText: String,
      unifiedLogText: String,
      readmeText: String
    ) {
      self.diagnoseText = diagnoseText
      self.diagnoseJSON = diagnoseJSON
      self.versionsText = versionsText
      self.diskStatusText = diskStatusText
      self.unifiedLogText = unifiedLogText
      self.readmeText = readmeText
    }
  }

  public struct ArchiveFile: Equatable, Sendable {
    public let name: String
    public let text: String

    public init(name: String, text: String) {
      self.name = name
      self.text = text
    }
  }

  public static func defaultFileName(
    date: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let year = calendar.component(.year, from: date)
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    return String(format: "NTFSMount-diagnose-%04d%02d%02d.zip", year, month, day)
  }

  public static func readmeText(locale: Locale? = nil) -> String {
    var lines = [
      L10n.t("diagnose.exportReadmeHeader", locale: locale),
      "",
      L10n.t("diagnose.exportPrivacy", locale: locale),
      "",
      L10n.t("diagnose.exportReadmeFiles", locale: locale),
    ]
    lines.append(contentsOf: archiveFiles.map { "- \($0)" })
    lines.append("")
    lines.append("log show --last \(logShowLast) --predicate '\(logShowPredicate)'")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  public static func files(from payload: Payload) -> [ArchiveFile] {
    [
      ArchiveFile(name: "README.txt", text: payload.readmeText),
      ArchiveFile(name: "diagnose.txt", text: payload.diagnoseText),
      ArchiveFile(name: "diagnose.json", text: payload.diagnoseJSON),
      ArchiveFile(name: "versions.txt", text: payload.versionsText),
      ArchiveFile(name: "disk-status.txt", text: payload.diskStatusText),
      ArchiveFile(name: "unified-log.txt", text: payload.unifiedLogText),
    ]
  }

  public static func snapshotJSON(_ snap: DiagnoseSnapshot) -> String {
    let data: Data
    do {
      data = try JSONSerialization.data(
        withJSONObject: snapshotObject(snap),
        options: [.prettyPrinted, .sortedKeys]
      )
    } catch {
      return "{\"error\":\"json_encode_failed\"}\n"
    }
    return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
  }

  public static func versionsText(snap: DiagnoseSnapshot, bundledFile: String?) -> String {
    var lines = [
      "# Live probe (EnvironmentDiagnose)",
      "pinned_fuse_t: \(emptyDash(snap.pinnedFuseT))",
      "system_fuse_t: \(emptyDash(snap.systemFuseTVersion))",
      "bundled_go_nfsv4: \(snap.bundledGoNfsv4)",
      "go_nfsv4_path: \(emptyDash(snap.goNfsv4Path))",
      "ntfs_3g_present: \(snap.bundledNtfs3g)",
      "ntfs_3g_path: \(emptyDash(snap.ntfs3gPath))",
      "ntfs_3g_version: \(emptyDash(snap.ntfs3gVersion))",
      "ntfs_3g_raw: \(emptyDash(snap.ntfs3gRaw))",
      "ntfs_3g_allowed: \(optionalFlag(snap.ntfs3gAllowed))",
      "ntfsfix_present: \(snap.bundledNtfsfix)",
      "",
      "# Bundled runtime/versions.txt",
    ]
    let bundled = bundledFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if bundled.isEmpty {
      lines.append("(not bundled)")
    } else {
      lines.append(bundled)
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  public static func diskStatusText(
    volumes: [NTFSVolume],
    diskutilList: String?,
    locale: Locale? = nil
  ) -> String {
    var lines = [
      L10n.t("diagnose.exportPrivacy", locale: locale),
      "",
    ]
    if volumes.isEmpty {
      lines.append(L10n.t("diagnose.exportNoVolumes", locale: locale))
      lines.append("")
    } else {
      for vol in volumes {
        lines.append("== \(vol.id) / \(vol.name) ==")
        lines.append("identifier: \(vol.id)")
        lines.append("name: \(vol.name)")
        lines.append("media: \(emptyDash(vol.mediaName))")
        lines.append("internal: \(vol.isInternal)")
        lines.append("mount_point: \(emptyDash(vol.mountPoint))")
        lines.append("writable_fuse: \(vol.isWritableFuse)")
        lines.append("read_only: \(vol.isReadOnlyMounted)")
        lines.append("encryption_hint: \(vol.hasEncryptionHint)")
        for row in DiskStatus.rows(volume: vol, locale: locale) {
          lines.append(row.line)
        }
        lines.append("")
      }
    }
    lines.append("== diskutil list ==")
    let list = diskutilList?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if list.isEmpty {
      lines.append(L10n.t("diagnose.exportDiskutilFailed", locale: locale))
    } else {
      lines.append(list)
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  public static func logShowUnavailableNote(
    status: Int32,
    detail: String,
    locale: Locale? = nil
  ) -> String {
    var lines = [
      L10n.t("diagnose.exportLogUnavailable", locale: locale),
      "status: \(status)",
      "command: log \(logShowArguments.joined(separator: " "))",
    ]
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      lines.append("")
      lines.append(trimmed)
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  public static func logShowEmptyNote(locale: Locale? = nil) -> String {
    """
    \(L10n.t("diagnose.exportLogEmpty", locale: locale))
    command: log \(logShowArguments.joined(separator: " "))

    """
  }

  static func snapshotObject(_ snap: DiagnoseSnapshot) -> [String: Any] {
    [
      "schema_version": 2,
      "source": "in-process",
      "arch": snap.arch,
      "apple_silicon": snap.appleSilicon,
      "macos_product_name": snap.macosProduct,
      "macos_version": snap.macosVersion,
      "fuse_t": [
        "bundled_present": snap.bundledGoNfsv4,
        "bundled_go_nfsv4": snap.goNfsv4Path,
        "pinned_version": snap.pinnedFuseT,
        "system_version": snap.systemFuseTVersion,
      ],
      "runtime": [
        "ntfs_3g_present": snap.bundledNtfs3g,
        "ntfs_3g_path": snap.ntfs3gPath,
        "ntfs_3g_version": snap.ntfs3gVersion,
        "ntfs_3g_raw": snap.ntfs3gRaw,
        "ntfs_3g_allowed": optionalJSON(snap.ntfs3gAllowed),
        "ntfsfix_present": snap.bundledNtfsfix,
        "go_nfsv4_present": snap.bundledGoNfsv4,
        "go_nfsv4_path": snap.goNfsv4Path,
        "pinned_fuse_t": snap.pinnedFuseT,
      ],
      "helper": [
        "socket_exists": snap.helperSocketExists,
        "ping": snap.helperPing,
      ],
      "conflicts": [
        "brew_macfuse": snap.brewMacFuse,
        "kext_macfuse": snap.kextMacFuse,
        "systemextensions_macfuse": snap.sysextMacFuse,
      ],
      "gatekeeper": [
        "quarantine": optionalJSON(snap.quarantine),
        "spctl": snap.spctl,
      ],
      "full_disk_access": [
        "app": snap.fullDiskAccess.rawValue,
        "path": FullDiskAccess.gatedPath,
        "note": """
        Readability of a gated path in this process; not a TCC.db scrape. \
        LaunchDaemon does not inherit the app grant.
        """,
      ],
    ]
  }

  private static func optionalJSON(_ value: Bool?) -> Any {
    if let value { return value }
    return NSNull()
  }

  private static func optionalFlag(_ value: Bool?) -> String {
    if let value { return value ? "true" : "false" }
    return "unknown"
  }

  private static func emptyDash(_ value: String) -> String {
    value.isEmpty ? "-" : value
  }
}
