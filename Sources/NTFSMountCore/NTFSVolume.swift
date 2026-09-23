import Foundation

public struct NTFSVolume: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let size: Int64
  public let mountPoint: String
  public let isWritableFuse: Bool
  public let isReadOnlyMounted: Bool
  public let isInternal: Bool
  public let mediaName: String
  public let usedBytes: Int64
  public let freeBytes: Int64

  public init(
    id: String,
    name: String,
    size: Int64,
    mountPoint: String,
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    isInternal: Bool,
    mediaName: String,
    usedBytes: Int64,
    freeBytes: Int64
  ) {
    self.id = id
    self.name = name
    self.size = size
    self.mountPoint = mountPoint
    self.isWritableFuse = isWritableFuse
    self.isReadOnlyMounted = isReadOnlyMounted
    self.isInternal = isInternal
    self.mediaName = mediaName
    self.usedBytes = usedBytes
    self.freeBytes = freeBytes
  }

  public var expectedMountPoint: String { mountPoint.isEmpty ? "/Volumes/\(name)" : mountPoint }

  public var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  public var stateLabel: String {
    if isWritableFuse { return "可写" }
    if isReadOnlyMounted { return "系统只读" }
    return "未挂载"
  }

  public var hasUsage: Bool {
    !mountPoint.isEmpty && (usedBytes + freeBytes) > 0
  }

  public var usageRatio: Double {
    let total = usedBytes + freeBytes
    guard total > 0 else { return 0 }
    return min(1, Double(usedBytes) / Double(total))
  }

  public static func scan(using catalog: DiskCatalog = DiskCatalogs.live) -> [NTFSVolume] {
    guard let list = catalog.listPlist() else { return [] }
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var ids: [String] = []
    for disk in disks {
      for part in disk["Partitions"] as? [[String: Any]] ?? [] {
        if let ident = part["DeviceIdentifier"] as? String {
          ids.append(ident)
        }
      }
      if let ident = disk["DeviceIdentifier"] as? String,
         disk["Partitions"] == nil {
        ids.append(ident)
      }
    }

    let fusePoints = catalog.fuseMountPoints()

    var out: [NTFSVolume] = []
    for ident in ids {
      guard let info = catalog.infoPlist(ident) else { continue }
      let fs = info["FilesystemName"] as? String ?? ""
      guard fs == "NTFS" else { continue }
      let name = info["VolumeName"] as? String
      let volumeName = (name?.isEmpty == false) ? name! : "NTFS-\(ident)"
      let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? 0
      let diskutilMp = info["MountPoint"] as? String ?? ""
      let expected = "/Volumes/\(volumeName)"
      let fuseMp = fusePoints.contains(diskutilMp) ? diskutilMp
        : (fusePoints.contains(expected) ? expected : "")
      let mp = fuseMp.isEmpty ? diskutilMp : fuseMp
      let fuse = !fuseMp.isEmpty
      let media = volumeMediaName(info: info, volumeName: volumeName)
      let diskutilFree = (info["VolumeFreeSpace"] as? NSNumber)?.int64Value
        ?? (info["FreeSpace"] as? NSNumber)?.int64Value
        ?? 0
      var used: Int64 = 0
      var free: Int64 = diskutilFree
      if !mp.isEmpty, let usage = catalog.fileSystemUsage(at: mp) {
        free = usage.free
        used = max(0, usage.total - usage.free)
      } else if size > 0, diskutilFree > 0 {
        used = max(0, size - diskutilFree)
      }
      let isInternalDisk = (info["Internal"] as? Bool == true)
        || (info["BusProtocol"] as? String == "Disk Image")
        || (info["BusProtocol"] as? String == "Apple Fabric")
      out.append(
        NTFSVolume(
          id: ident,
          name: volumeName,
          size: size,
          mountPoint: mp,
          isWritableFuse: fuse,
          isReadOnlyMounted: !mp.isEmpty && !fuse,
          isInternal: isInternalDisk,
          mediaName: media,
          usedBytes: used,
          freeBytes: free
        )
      )
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

func volumeMediaName(info: [String: Any], volumeName: String) -> String {
  let media = info["MediaName"] as? String ?? ""
  if !media.isEmpty, media != volumeName { return media }
  let proto = info["BusProtocol"] as? String ?? ""
  if !proto.isEmpty { return proto }
  return ""
}
