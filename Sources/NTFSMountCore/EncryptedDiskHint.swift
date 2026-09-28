import Foundation

/// diskutil clues only. macOS cannot confirm BitLocker; absence is not a true negative.
public struct PossibleEncryptedDisk: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let hint: String

  public init(id: String, name: String, hint: String) {
    self.id = id
    self.name = name
    self.hint = hint
  }
}

public enum EncryptedDiskHint {
  public static var userMessage: String { userMessage(locale: nil) }

  public static func userMessage(locale: Locale?) -> String {
    L10n.t("encrypted.message", locale: locale)
  }

  public static func warning(from info: [String: Any], content: String = "") -> String? {
    let fs = (info["FilesystemName"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let enc = boolFlag(info["Encrypted"])
    let blob = "\(fs) \(content) \(info["VolumeName"] as? String ?? "")".lowercased()
    if blob.contains("bitlocker") { return userMessage }
    let windowsish = blob.contains("ntfs")
      || content.localizedCaseInsensitiveContains("Microsoft")
      || content.localizedCaseInsensitiveContains("Windows")
    if enc && windowsish { return userMessage }
    if content.localizedCaseInsensitiveContains("Microsoft Basic Data"),
       !isKnownDataFS(fs) {
      return userMessage
    }
    return nil
  }

  public static func scan(using catalog: DiskCatalog = DiskCatalogs.live) -> [PossibleEncryptedDisk] {
    guard let list = catalog.listPlist() else { return [] }
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var out: [PossibleEncryptedDisk] = []
    var seen = Set<String>()
    for disk in disks {
      collect(disk, catalog: catalog, into: &out, seen: &seen)
      for part in disk["Partitions"] as? [[String: Any]] ?? [] {
        collect(part, catalog: catalog, into: &out, seen: &seen)
      }
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func collect(
    _ node: [String: Any],
    catalog: DiskCatalog,
    into out: inout [PossibleEncryptedDisk],
    seen: inout Set<String>
  ) {
    guard let ident = node["DeviceIdentifier"] as? String, seen.insert(ident).inserted else { return }
    let content = node["Content"] as? String ?? ""
    let info = catalog.infoPlist(ident) ?? node
    guard let warning = warning(from: info, content: content) else { return }
    let name = (info["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? (info["MediaName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? ident
    out.append(PossibleEncryptedDisk(id: ident, name: name, hint: warning))
  }

  private static func isKnownDataFS(_ fs: String) -> Bool {
    let u = fs.uppercased()
    return u == "NTFS" || u == "EXFAT" || u.contains("FAT") || u == "APFS" || u == "HFS+"
  }

  private static func boolFlag(_ value: Any?) -> Bool {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    if let s = value as? String { return s.lowercased() == "yes" || s == "1" }
    return false
  }
}
