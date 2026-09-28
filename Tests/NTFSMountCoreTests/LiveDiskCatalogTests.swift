import Foundation
import NTFSMountCore
import XCTest

final class MockDiskUtilClient: DiskUtilClient {
  var listData: Data?
  var infoData: [String: Data] = [:]
  var mountText: String?
  var usage: [String: (Int64, Int64)] = [:]

  func listPlistData() -> Data? { listData }
  func infoPlistData(_ identifier: String) -> Data? { infoData[identifier] }
  func mountOutput() -> String? { mountText }
  func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? { usage[path] }
}

final class LiveDiskCatalogTests: XCTestCase {
  func testParsesMixedDiskutilPlistFixturesWithoutAPhysicalDisk() {
    let client = mixedFixtureClient()
    let catalog = LiveDiskCatalog(client: client)

    XCTAssertEqual(catalog.infoPlist("disk0s2")?["FilesystemName"] as? String, "APFS")
    XCTAssertEqual(catalog.infoPlist("disk4s1")?["FilesystemName"] as? String, "NTFS")
    XCTAssertEqual(catalog.infoPlist("disk4s1")?["VolumeName"] as? String, "WIN_DATA")
    XCTAssertEqual(catalog.infoPlist("disk8s1")?["VolumeName"] as? String, "My Passport")
    XCTAssertEqual(catalog.infoPlist("disk9s1")?["VolumeName"] as? String, "移动硬盘")
    XCTAssertEqual(
      catalog.fuseMountPoints(),
      ["/Volumes/My Passport"]
    )

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertFalse(vols.contains { $0.id == "disk0s2" }, "APFS internal must not appear as NTFS")

    let external = vols.first { $0.id == "disk4s1" }
    XCTAssertEqual(external?.name, "WIN_DATA")
    XCTAssertFalse(external?.isInternal ?? true)
    XCTAssertFalse(external?.hasEncryptionHint ?? true)
    XCTAssertEqual(external?.mediaName, "SanDisk")

    let image = vols.first { $0.id == "disk5s1" }
    XCTAssertEqual(image?.name, "ImageNTFS")
    XCTAssertEqual(image?.isInternal, true, "Disk Image is treated as internal")

    let encrypted = vols.first { $0.id == "disk6s1" }
    XCTAssertEqual(encrypted?.name, "SECRET")
    XCTAssertEqual(encrypted?.hasEncryptionHint, true)

    let passport = vols.first { $0.id == "disk8s1" }
    XCTAssertEqual(passport?.mountPoint, "/Volumes/My Passport")
    XCTAssertEqual(passport?.expectedMountPoint, "/Volumes/My Passport")
    XCTAssertEqual(passport?.isWritableFuse, true)
    XCTAssertEqual(passport?.usedBytes, 600_000_000)
    XCTAssertEqual(passport?.freeBytes, 400_000_000)

    let cjk = vols.first { $0.id == "disk9s1" }
    XCTAssertEqual(cjk?.name, "移动硬盘")
    XCTAssertEqual(cjk?.mountPoint, "")
    XCTAssertEqual(cjk?.expectedMountPoint, "/Volumes/移动硬盘")
    XCTAssertEqual(cjk?.isWritableFuse, false)

    let whole = vols.first { $0.id == "disk10" }
    XCTAssertEqual(whole?.name, "NTFS-disk10")
    XCTAssertEqual(whole?.isReadOnlyMounted, true)
  }

  func testMissingDiskutilReturnsNilListAndEmptyScan() {
    let client = MockDiskUtilClient()
    let catalog = LiveDiskCatalog(client: client)
    XCTAssertNil(catalog.listPlist())
    XCTAssertEqual(NTFSVolume.scan(using: catalog), [])
    XCTAssertEqual(catalog.fuseMountPoints(), [])
    XCTAssertNil(catalog.fileSystemUsage(at: "/Volumes/WIN_DATA"))
  }

  func testInvalidPlistDataIsNotACatalog() {
    let client = MockDiskUtilClient()
    client.listData = Data("not a plist".utf8)
    client.infoData["disk4s1"] = Data("<plist></plist>".utf8)
    let catalog = LiveDiskCatalog(client: client)
    XCTAssertNil(catalog.listPlist())
    XCTAssertNil(catalog.infoPlist("disk4s1"))
  }

  func testDefaultClientReadsRealDiskutilListWithoutNeedingNTFS() {
    let client = ProcessDiskUtilClient()
    XCTAssertNotNil(client.listPlistData(), "diskutil list -plist must run on this Mac")
    XCTAssertNotNil(client.mountOutput())
    let tmp = FileManager.default.temporaryDirectory.path
    let usage = client.fileSystemUsage(at: tmp)
    XCTAssertNotNil(usage)
    XCTAssertGreaterThan(usage?.total ?? 0, 0)

    let list = LiveDiskCatalog().listPlist()
    XCTAssertNotNil(list?["AllDisksAndPartitions"])
    let missing = LiveDiskCatalog(client: client).infoPlist("disk99999s99")
    XCTAssertNotNil(missing?["ErrorMessage"] as? String)
    XCTAssertNil(missing?["FilesystemName"])
  }
}

private func mixedFixtureClient() -> MockDiskUtilClient {
  let client = MockDiskUtilClient()
  client.listData = xmlPlist(["AllDisksAndPartitions": mixedListDisks()])
  client.infoData = mixedInfoPlists()
  client.mountText = """
  /dev/disk1s1 on / (apfs, local, journaled)
  localhost:/ on /Volumes/My Passport (nfs, nodev, nosuid, mounted by alice)
  """
  client.usage["/Volumes/My Passport"] = (1_000_000_000, 400_000_000)
  return client
}

private func mixedListDisks() -> [[String: Any]] {
  [
    listedDisk("disk0", slices: [("disk0s2", "Apple_APFS")]),
    listedDisk("disk4", slices: [("disk4s1", "Microsoft Basic Data")]),
    listedDisk("disk5", slices: [("disk5s1", "")]),
    listedDisk("disk6", slices: [("disk6s1", "Microsoft Basic Data")]),
    listedDisk("disk8", slices: [("disk8s1", "")]),
    listedDisk("disk9", slices: [("disk9s1", "")]),
    ["DeviceIdentifier": "disk10", "Content": "Microsoft Basic Data"],
  ]
}

private func listedDisk(_ id: String, slices: [(String, String)]) -> [String: Any] {
  [
    "DeviceIdentifier": id,
    "Partitions": slices.map { slice -> [String: Any] in
      var part: [String: Any] = ["DeviceIdentifier": slice.0]
      if !slice.1.isEmpty { part["Content"] = slice.1 }
      return part
    },
  ]
}

private func mixedInfoPlists() -> [String: Data] {
  [
    "disk0s2": volumeInfo(
      fs: "APFS", name: "Macintosh HD", size: 500_000_000_000,
      isInternal: true, proto: "Apple Fabric"
    ),
    "disk4s1": volumeInfo(
      fs: "NTFS", name: "WIN_DATA", size: 16_000_000_000,
      proto: "USB", media: "SanDisk", free: 9_000_000_000
    ),
    "disk5s1": volumeInfo(fs: "NTFS", name: "ImageNTFS", size: 2_000_000_000, proto: "Disk Image"),
    "disk6s1": volumeInfo(
      fs: "NTFS", name: "SECRET", size: 8_000_000_000, proto: "USB", encrypted: true
    ),
    "disk8s1": volumeInfo(
      fs: "NTFS", name: "My Passport", size: 1_000_000_000,
      proto: "USB", mount: "/Volumes/My Passport", free: 400_000_000
    ),
    "disk9s1": volumeInfo(fs: "NTFS", name: "移动硬盘", size: 2_000_000_000, proto: "USB"),
    "disk10": volumeInfo(
      fs: "NTFS", name: "", size: 4_000_000_000, proto: "USB", mount: "/Volumes/Untitled"
    ),
  ]
}

private func volumeInfo(
  fs: String,
  name: String,
  size: Int64,
  isInternal: Bool = false,
  proto: String,
  media: String = "",
  mount: String = "",
  free: Int64 = 0,
  encrypted: Bool = false
) -> Data {
  var dict: [String: Any] = [
    "FilesystemName": fs,
    "VolumeName": name,
    "TotalSize": NSNumber(value: size),
    "Internal": isInternal,
    "BusProtocol": proto,
  ]
  if !media.isEmpty { dict["MediaName"] = media }
  if !mount.isEmpty { dict["MountPoint"] = mount }
  if free > 0 { dict["VolumeFreeSpace"] = NSNumber(value: free) }
  if encrypted { dict["Encrypted"] = true }
  return xmlPlist(dict)
}

private func xmlPlist(_ object: [String: Any]) -> Data {
  try! PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
}
