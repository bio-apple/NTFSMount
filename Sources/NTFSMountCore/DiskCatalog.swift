import Foundation

public protocol DiskCatalog {
  func listPlist() -> [String: Any]?
  func infoPlist(_ identifier: String) -> [String: Any]?
  func fuseMountPoints() -> Set<String>
  func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)?
}

public struct LiveDiskCatalog: DiskCatalog {
  public init() {}

  public func listPlist() -> [String: Any]? {
    diskutilPlist(["list", "-plist"])
  }

  public func infoPlist(_ identifier: String) -> [String: Any]? {
    diskutilPlist(["info", "-plist", identifier])
  }

  public func fuseMountPoints() -> Set<String> {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
    let data = (proc.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    let text = String(data: data, encoding: .utf8) ?? ""
    var fuse = Set<String>()
    for line in text.split(separator: "\n") {
      let s = String(line)
      let lower = s.lowercased()
      guard lower.contains("macfuse")
        || lower.contains("osxfuse")
        || lower.contains("fuse-t")
        || lower.contains("fuset")
        || lower.contains("ntfs-3g")
        || s.contains(" fuse,")
      else { continue }
      if let range = s.range(of: " on "),
         let end = s.range(of: " (") {
        fuse.insert(String(s[range.upperBound..<end.lowerBound]))
      }
    }
    return fuse
  }

  public func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? {
    guard let vals = try? FileManager.default.attributesOfFileSystem(forPath: path),
          let total = vals[.systemSize] as? NSNumber,
          let free = vals[.systemFreeSize] as? NSNumber
    else { return nil }
    return (total.int64Value, free.int64Value)
  }
}

public enum DiskCatalogs {
  public static var live: DiskCatalog = LiveDiskCatalog()
}

func diskutilPlist(_ args: [String]) -> [String: Any]? {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
  proc.arguments = args
  let out = Pipe()
  proc.standardOutput = out
  proc.standardError = Pipe()
  do {
    try proc.run()
    proc.waitUntilExit()
  } catch {
    return nil
  }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
}
