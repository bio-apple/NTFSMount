import Foundation

public struct FormatDisk: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let size: Int64
  public let fsHint: String
  public let serial: String
  public let mediaName: String

  public init(
    id: String,
    name: String,
    size: Int64,
    fsHint: String,
    serial: String = "",
    mediaName: String = ""
  ) {
    self.id = id
    self.name = name
    self.size = size
    self.fsHint = fsHint
    self.serial = serial
    self.mediaName = mediaName
  }

  public var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  public var suggestedLabel: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == id { return "NTFS" }
    return String(trimmed.prefix(32))
  }

  public static func scan(using catalog: DiskCatalog = DiskCatalogs.live) -> [FormatDisk] {
    guard let list = catalog.listPlist() else { return [] }
    let protected = protectedDisks(using: catalog)
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var out: [FormatDisk] = []
    for disk in disks {
      guard let ident = disk["DeviceIdentifier"] as? String,
            ident.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil
      else { continue }
      guard let info = catalog.infoPlist(ident) else { continue }
      if info["Internal"] as? Bool == true { continue }
      let proto = info["BusProtocol"] as? String ?? ""
      if proto == "Disk Image" || proto == "Apple Fabric" { continue }
      if info["VirtualOrPhysical"] as? String == "Virtual" { continue }
      if protected.contains(ident) { continue }
      let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? 0
      guard size > 0 else { continue }
      let media = info["MediaName"] as? String ?? ""
      let parts = disk["Partitions"] as? [[String: Any]] ?? []
      var hint = "未格式化"
      var volName = ""
      var partInfo: [String: Any]?
      for part in parts {
        let content = part["Content"] as? String ?? ""
        if content.uppercased().contains("EFI") { continue }
        if let pid = part["DeviceIdentifier"] as? String,
           let pinfo = catalog.infoPlist(pid) {
          partInfo = pinfo
          let fs = pinfo["FilesystemName"] as? String ?? ""
          hint = fs.isEmpty ? (content.isEmpty ? hint : content) : fs
          volName = pinfo["VolumeName"] as? String ?? ""
        } else if !content.isEmpty {
          hint = content
        }
        break
      }
      let name: String
      if !volName.isEmpty {
        name = volName
      } else if !media.isEmpty {
        name = media
      } else {
        name = ident
      }
      out.append(FormatDisk(
        id: ident,
        name: name,
        size: size,
        fsHint: hint,
        serial: serial(from: info, part: partInfo),
        mediaName: media
      ))
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  static func protectedDisks(using catalog: DiskCatalog) -> Set<String> {
    var out = Set<String>()
    guard let info = catalog.infoPlist("/") else { return out }
    if let parent = info["ParentWholeDisk"] as? String {
      out.insert(parent)
      out.insert(FormatPolicy.wholeDiskId(parent))
    }
    if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
      for store in stores {
        if let ident = store["APFSPhysicalStore"] as? String {
          out.insert(ident)
          out.insert(FormatPolicy.wholeDiskId(ident))
        }
      }
    }
    return out
  }

  static func serial(from info: [String: Any], part: [String: Any]?) -> String {
    for key in ["DiskUUID", "VolumeUUID"] {
      if let value = info[key] as? String, !value.isEmpty { return value }
      if let value = part?[key] as? String, !value.isEmpty { return value }
    }
    return ""
  }
}
