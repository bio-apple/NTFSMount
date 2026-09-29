import Foundation

public protocol DiskCatalog {
  func listPlist() -> [String: Any]?
  func infoPlist(_ identifier: String) -> [String: Any]?
  func fuseMountPoints() -> Set<String>
  /// Subset of `fuseMountPoints()` that is mounted read-only (`mount(8)` `read-only` flag).
  func readOnlyFuseMountPoints() -> Set<String>
  func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)?
}

/// Raw diskutil / mount / statfs I/O. Production uses Process + CommandPath (system dirs only).
public protocol DiskUtilClient {
  func listPlistData() -> Data?
  func infoPlistData(_ identifier: String) -> Data?
  func mountOutput() -> String?
  func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)?
}

public struct ProcessDiskUtilClient: DiskUtilClient {
  public init() {}

  public func listPlistData() -> Data? {
    runDiskutil(["list", "-plist"])
  }

  public func infoPlistData(_ identifier: String) -> Data? {
    runDiskutil(["info", "-plist", identifier])
  }

  public func mountOutput() -> String? {
    guard let mount = CommandPath.find("mount") else { return nil }
    return runText(executable: mount)
  }

  public func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? {
    guard let vals = try? FileManager.default.attributesOfFileSystem(forPath: path),
          let total = vals[.systemSize] as? NSNumber,
          let free = vals[.systemFreeSize] as? NSNumber
    else { return nil }
    return (total.int64Value, free.int64Value)
  }

  private func runDiskutil(_ args: [String]) -> Data? {
    guard let diskutil = CommandPath.find("diskutil") else { return nil }
    return runData(executable: diskutil, arguments: args)
  }

  private func runText(executable: String) -> String? {
    guard let data = runData(executable: executable, arguments: []) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func runData(executable: String, arguments: [String]) -> Data? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do {
      try proc.run()
      proc.waitUntilExit()
    } catch {
      return nil
    }
    return out.fileHandleForReading.readDataToEndOfFile()
  }
}

public struct LiveDiskCatalog: DiskCatalog {
  private let client: DiskUtilClient

  public init(client: DiskUtilClient = ProcessDiskUtilClient()) {
    self.client = client
  }

  public func listPlist() -> [String: Any]? {
    parsePlist(client.listPlistData())
  }

  public func infoPlist(_ identifier: String) -> [String: Any]? {
    parsePlist(client.infoPlistData(identifier))
  }

  public func fuseMountPoints() -> Set<String> {
    guard let text = client.mountOutput() else { return [] }
    return FuseMountLine.fuseMountPoints(fromMountOutput: text)
  }

  public func readOnlyFuseMountPoints() -> Set<String> {
    guard let text = client.mountOutput() else { return [] }
    return Set(
      FuseMountLine.fuseMountStates(fromMountOutput: text)
        .filter { $0.value }
        .keys
    )
  }

  public func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? {
    client.fileSystemUsage(at: path)
  }
}

public enum DiskCatalogs {
  public static var live: DiskCatalog = LiveDiskCatalog()
}

func parsePlist(_ data: Data?) -> [String: Any]? {
  guard let data else { return nil }
  return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
}
