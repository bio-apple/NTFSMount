import Foundation
import NTFSMountCore
import XCTest

final class MockCatalog: DiskCatalog {
  var list: [String: Any] = [:]
  var info: [String: [String: Any]] = [:]
  var fuse: Set<String> = []
  var usage: [String: (Int64, Int64)] = [:]

  func listPlist() -> [String: Any]? { list }
  func infoPlist(_ identifier: String) -> [String: Any]? { info[identifier] }
  func fuseMountPoints() -> Set<String> { fuse }
  func fileSystemUsage(at path: String) -> (total: Int64, free: Int64)? { usage[path] }
}

final class FuseMountLineTests: XCTestCase {
  func testFuseMountPointsRecognizesFuseTGoNfsv4Line() {
    let mount = """
    localhost:/ on /Volumes/WIN_DATA (nfs, nodev, nosuid, mounted by alice)
    """
    XCTAssertTrue(FuseMountLine.isOurFuseMount(mount))
    XCTAssertEqual(FuseMountLine.mountPoint(from: mount), "/Volumes/WIN_DATA")
    XCTAssertEqual(FuseMountLine.fuseMountPoints(fromMountOutput: mount), ["/Volumes/WIN_DATA"])
  }

  func testFuseMountPointsRecognizesClassicFuseBackends() {
    let mount = """
    /dev/disk4s1 on /Volumes/NTFS_A (ntfs-3g, local, nosuid)
    /dev/disk5s1 on /Volumes/NTFS_B (macfuse, local, nosuid)
    /dev/disk6s1 on /Volumes/NTFS_C (fuse-t, local, nosuid)
    /dev/disk7s1 on /Volumes/NTFS_D (osxfuse, local, nosuid)
    /dev/disk8s1 on /Volumes/NTFS_E (local, fuse, nosuid)
    """
    let points = FuseMountLine.fuseMountPoints(fromMountOutput: mount)
    XCTAssertEqual(points.count, 5)
    XCTAssertTrue(points.isSuperset(of: [
      "/Volumes/NTFS_A",
      "/Volumes/NTFS_B",
      "/Volumes/NTFS_C",
      "/Volumes/NTFS_D",
      "/Volumes/NTFS_E",
    ]))
  }

  func testFuseMountPointsSkipsUnrelatedMountLines() {
    let mount = """
    map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)
    /dev/disk1s1 on / (apfs, local, journaled)
    localhost:/ on /Volumes/FUSE_VOL (nfs, nodev, nosuid)
    """
    XCTAssertEqual(FuseMountLine.fuseMountPoints(fromMountOutput: mount), ["/Volumes/FUSE_VOL"])
  }

  func testFuseMountPointsKeepsSpacesAndCJKInOnePath() {
    let mount = """
    localhost:/ on /Volumes/My Passport (nfs, nodev, nosuid, mounted by alice)
    /dev/disk5s1 on /Volumes/移动硬盘 (ntfs-3g, local, nosuid)
    """
    let points = FuseMountLine.fuseMountPoints(fromMountOutput: mount)
    XCTAssertEqual(points, ["/Volumes/My Passport", "/Volumes/移动硬盘"])
    XCTAssertEqual(
      FuseMountLine.mountPoint(from: "localhost:/ on /Volumes/My Passport (nfs, nodev)"),
      "/Volumes/My Passport"
    )
  }
}

final class NTFSVolumeScanTests: XCTestCase {
  func testScanKeepsWritableFuseNTFSAndSkipsExFAT() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        [
          "DeviceIdentifier": "disk4",
          "Partitions": [["DeviceIdentifier": "disk4s1"]],
        ],
        [
          "DeviceIdentifier": "disk5",
          "Partitions": [["DeviceIdentifier": "disk5s1"]],
        ],
      ],
    ]
    catalog.info["disk4s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "BANDISK",
      "TotalSize": NSNumber(value: 8_000_000_000),
      "MountPoint": "/Volumes/BANDISK",
      "Internal": false,
      "BusProtocol": "USB",
      "VolumeFreeSpace": NSNumber(value: 3_000_000_000),
    ]
    catalog.info["disk5s1"] = [
      "FilesystemName": "ExFAT",
      "VolumeName": "CAMERA",
      "TotalSize": NSNumber(value: 1_000_000_000),
      "MountPoint": "/Volumes/CAMERA",
      "Internal": false,
    ]
    catalog.fuse = ["/Volumes/BANDISK"]
    catalog.usage["/Volumes/BANDISK"] = (8_000_000_000, 3_000_000_000)

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertEqual(vols.map(\.id), ["disk4s1"])
    XCTAssertEqual(vols[0].name, "BANDISK")
    XCTAssertTrue(vols[0].isWritableFuse)
    XCTAssertFalse(vols[0].isInternal)
    XCTAssertEqual(vols[0].mediaName, "USB")
    XCTAssertFalse(vols[0].hasEncryptionHint)
  }

  func testScanMarksInternalNTFSAndReadOnlySystemMount() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [[
        "DeviceIdentifier": "disk3",
        "Partitions": [["DeviceIdentifier": "disk3s1"]],
      ]],
    ]
    catalog.info["disk3s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "BOOTCAMP",
      "TotalSize": NSNumber(value: 40_000_000_000),
      "MountPoint": "/Volumes/BOOTCAMP",
      "Internal": true,
      "BusProtocol": "Apple Fabric",
    ]

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertEqual(vols.count, 1)
    XCTAssertTrue(vols[0].isInternal)
    XCTAssertTrue(vols[0].isReadOnlyMounted)
    XCTAssertFalse(vols[0].isWritableFuse)
  }

  func testExpectedMountPointKeepsSpacesAndCJKAsSinglePath() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        [
          "DeviceIdentifier": "disk8",
          "Partitions": [["DeviceIdentifier": "disk8s1"]],
        ],
        [
          "DeviceIdentifier": "disk9",
          "Partitions": [["DeviceIdentifier": "disk9s1"]],
        ],
      ],
    ]
    catalog.info["disk8s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "My Passport",
      "TotalSize": NSNumber(value: 1_000_000_000),
      "MountPoint": "/Volumes/My Passport",
      "Internal": false,
      "BusProtocol": "USB",
    ]
    catalog.info["disk9s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "移动硬盘",
      "TotalSize": NSNumber(value: 2_000_000_000),
      "Internal": false,
      "BusProtocol": "USB",
    ]
    catalog.fuse = ["/Volumes/My Passport"]
    catalog.usage["/Volumes/My Passport"] = (1_000_000_000, 400_000_000)

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertEqual(vols.map(\.name).sorted(), ["My Passport", "移动硬盘"])
    let passport = vols.first { $0.name == "My Passport" }!
    let cjk = vols.first { $0.name == "移动硬盘" }!
    XCTAssertEqual(passport.mountPoint, "/Volumes/My Passport")
    XCTAssertEqual(passport.expectedMountPoint, "/Volumes/My Passport")
    XCTAssertTrue(passport.isWritableFuse)
    XCTAssertEqual(cjk.mountPoint, "")
    XCTAssertEqual(cjk.expectedMountPoint, "/Volumes/移动硬盘")
  }

  func testScanMarksEncryptionHintFromDiskutilWithoutLockState() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [[
        "DeviceIdentifier": "disk4",
        "Partitions": [[
          "DeviceIdentifier": "disk4s1",
          "Content": "Microsoft Basic Data",
        ]],
      ]],
    ]
    catalog.info["disk4s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "WIN",
      "TotalSize": NSNumber(value: 8_000_000_000),
      "Encrypted": true,
      "Internal": false,
      "BusProtocol": "USB",
    ]

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertEqual(vols.map(\.id), ["disk4s1"])
    XCTAssertTrue(vols[0].hasEncryptionHint)
    let zh = Locale(identifier: "zh-Hans")
    let bitlocker = DiskStatus.rows(volume: vols[0], locale: zh)
      .first { $0.label == "BitLocker" }?.value
    XCTAssertEqual(bitlocker, "可能加密")
    XCTAssertNotEqual(bitlocker, "Locked")
    XCTAssertNotEqual(bitlocker, "Unlocked")
  }

  func testScanKeepsUnmountedExternalNTFSForAutoMount() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [[
        "DeviceIdentifier": "disk6",
        "Partitions": [["DeviceIdentifier": "disk6s1"]],
      ]],
    ]
    catalog.info["disk6s1"] = [
      "FilesystemName": "NTFS",
      "VolumeName": "WIN_DATA",
      "TotalSize": NSNumber(value: 16_000_000_000),
      "Internal": false,
      "BusProtocol": "USB",
    ]

    let vols = NTFSVolume.scan(using: catalog)
    XCTAssertEqual(vols.map(\.id), ["disk6s1"])
    XCTAssertEqual(vols[0].mountPoint, "")
    XCTAssertFalse(vols[0].isWritableFuse)
    XCTAssertFalse(vols[0].isInternal)
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: vols[0].isInternal,
        isWritableFuse: vols[0].isWritableFuse,
        userSkippedUnmount: false,
        alreadyAttempted: false
      )
    )
  }

  func testFormatScanSkipsInternalAndSystemDisk() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk3", "Partitions": [["DeviceIdentifier": "disk3s1"]]],
        ["DeviceIdentifier": "disk4", "Partitions": [["DeviceIdentifier": "disk4s1"]]],
      ],
    ]
    catalog.info["/"] = ["ParentWholeDisk": "disk3"]
    catalog.info["disk3"] = [
      "Internal": true,
      "TotalSize": NSNumber(value: 500_000_000_000),
      "BusProtocol": "Apple Fabric",
    ]
    catalog.info["disk4"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 8_000_000_000),
      "BusProtocol": "USB",
      "MediaName": "SanDisk",
      "DiskUUID": "ABCD-1234-DISK",
    ]
    catalog.info["disk4s1"] = [
      "FilesystemName": "ExFAT",
      "VolumeName": "CAMERA",
      "VolumeUUID": "VOL-999",
    ]

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk4"])
    XCTAssertEqual(disks[0].name, "CAMERA")
    XCTAssertEqual(disks[0].fsHint, "ExFAT")
    XCTAssertEqual(disks[0].serial, "ABCD-1234-DISK")
    XCTAssertEqual(disks[0].mediaName, "SanDisk")
  }

  func testFormatScanIgnoresHelperScratchVolumeName() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk4", "Partitions": [["DeviceIdentifier": "disk4s1"]]],
      ],
    ]
    catalog.info["disk4"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 62_000_000_000),
      "BusProtocol": "USB",
      "MediaName": "USB DISK",
    ]
    catalog.info["disk4s1"] = [
      "FilesystemName": "ExFAT",
      "VolumeName": FormatPolicy.placeholderVolumeName,
    ]

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk4"])
    XCTAssertEqual(disks[0].name, "USB DISK", "the scratch name must not become the disk name")
    XCTAssertEqual(disks[0].suggestedLabel, "USB DISK")
    XCTAssertNotEqual(disks[0].suggestedLabel, FormatPolicy.placeholderVolumeName)
    XCTAssertEqual(disks[0].fsHint, "ExFAT")
  }

  func testFormatScanProtectsAPFSPhysicalStoreEvenIfNotInternal() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk0", "Partitions": [["DeviceIdentifier": "disk0s2"]]],
        ["DeviceIdentifier": "disk4", "Partitions": [["DeviceIdentifier": "disk4s1"]]],
      ],
    ]
    catalog.info["/"] = [
      "ParentWholeDisk": "disk3",
      "APFSPhysicalStores": [
        ["APFSPhysicalStore": "disk0s2"],
      ],
    ]
    catalog.info["disk0"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 500_000_000_000),
      "BusProtocol": "PCI",
    ]
    catalog.info["disk4"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 8_000_000_000),
      "BusProtocol": "USB",
      "MediaName": "SanDisk",
    ]
    catalog.info["disk4s1"] = [
      "FilesystemName": "ExFAT",
      "VolumeName": "CAMERA",
    ]

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk4"])
    XCTAssertFalse(disks.contains(where: { $0.id == "disk0" }))
  }

  func testFormatScanSkipsVirtualAndZeroSize() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk6", "Partitions": [["DeviceIdentifier": "disk6s1"]]],
        ["DeviceIdentifier": "disk7", "Partitions": [["DeviceIdentifier": "disk7s1"]]],
        ["DeviceIdentifier": "disk8", "Partitions": [["DeviceIdentifier": "disk8s1"]]],
      ],
    ]
    catalog.info["disk6"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 8_000_000_000),
      "VirtualOrPhysical": "Virtual",
      "BusProtocol": "USB",
    ]
    catalog.info["disk7"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 0),
      "BusProtocol": "USB",
    ]
    catalog.info["disk8"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 4_000_000_000),
      "BusProtocol": "USB",
      "MediaName": "Stick",
    ]
    catalog.info["disk8s1"] = [
      "FilesystemName": "FAT32",
      "VolumeName": "KEY",
    ]

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk8"])
  }

  func testFormatSerialFallsBackToPartVolumeUUIDAndEmptyNameSuggestsNTFS() {
    let catalog = MockCatalog()
    catalog.list = [
      "AllDisksAndPartitions": [
        ["DeviceIdentifier": "disk9", "Partitions": [["DeviceIdentifier": "disk9s1"]]],
      ],
    ]
    catalog.info["disk9"] = [
      "Internal": false,
      "TotalSize": NSNumber(value: 2_000_000_000),
      "BusProtocol": "USB",
    ]
    catalog.info["disk9s1"] = [
      "FilesystemName": "ExFAT",
      "VolumeUUID": "VOL-FROM-PART",
      "VolumeName": "",
    ]

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk9"])
    XCTAssertEqual(disks[0].serial, "VOL-FROM-PART")
    XCTAssertEqual(disks[0].name, "disk9")
    XCTAssertEqual(disks[0].suggestedLabel, "NTFS")
    XCTAssertEqual(FormatDisk(id: "disk4", name: "  ", size: 1, fsHint: "").suggestedLabel, "NTFS")
  }
}
