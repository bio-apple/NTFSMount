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

final class VolumeHealthTests: XCTestCase {
  func testDirtyAndHibernationAreReadOnly() {
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("Windows is hibernated, refused to mount."))
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("hiberfil.sys present, unsafe state"))
    XCTAssertFalse(VolumeHealth.looksDirtyOrHibernated("Mounted successfully"))
    XCTAssertEqual(VolumeHealth.advice(for: "hibernated", success: true), .readOnlyDirty)
  }

  func testDistinguishesDirtyFromHibernated() {
    XCTAssertTrue(VolumeHealth.looksHibernated("Windows is hibernated, refused to mount."))
    XCTAssertTrue(VolumeHealth.looksHibernated("hiberfil.sys present"))
    XCTAssertFalse(VolumeHealth.looksHibernated("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirty("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirty("The disk contains an unclean file system"))
    XCTAssertTrue(VolumeHealth.looksDirty("Windows fast restart left the volume dirty"))
    XCTAssertFalse(VolumeHealth.looksDirty("Mounted successfully"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("volume is dirty"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("unclean / fast restart"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("Windows is hibernated"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("Volume is dirty. Windows is hibernated."))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("classify: volume is dirty"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: Windows is hibernated"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: dirty/hibernation"))
  }

  func testKextBlockIsClassified() {
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("FSKit module is disabled"))
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("kernel extension denied"))
    XCTAssertEqual(VolumeHealth.advice(for: "fskit unavailable", success: false), .failedKext)
  }

  func testReadOnlyStatusExplainsCause() {
    XCTAssertEqual(
      VolumeHealth.shortStatus(busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: nil),
      "只读 · 系统 NTFS"
    )
    XCTAssertEqual(
      VolumeHealth.shortStatus(busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty),
      "只读 · 休眠/未正常关机"
    )
    XCTAssertTrue(
      VolumeHealth.detailStatus(isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty)
        .contains("彻底关机")
    )
  }
}

final class OnboardingCopyTests: XCTestCase {
  func testAgreeIsPrimaryAndBodyMentionsHelper() {
    XCTAssertEqual(OnboardingCopy.quitTitle, "退出")
    XCTAssertEqual(OnboardingCopy.agreeTitle, "同意并继续")
    let body = OnboardingCopy.body(notarized: false)
    XCTAssertTrue(body.contains("仍要打开"))
    XCTAssertTrue(body.contains("xattr -d com.apple.quarantine"))
    XCTAssertTrue(body.contains("管理员密码"))
    XCTAssertTrue(body.contains("go-nfsv4"))
    XCTAssertTrue(body.contains("回车即同意"))
    XCTAssertFalse(OnboardingCopy.body(notarized: true).contains("当前构建未公证"))
  }
}

final class FormatPolicyTests: XCTestCase {
  func testConfirmRequiresExactCurrentName() {
    XCTAssertTrue(FormatPolicy.confirms(typed: "BANDISK", currentName: "BANDISK"))
    XCTAssertFalse(FormatPolicy.confirms(typed: "bandisk", currentName: "BANDISK"))
    XCTAssertFalse(FormatPolicy.confirms(typed: "", currentName: "BANDISK"))
    XCTAssertFalse(FormatPolicy.confirms(typed: "BANDISK ", currentName: "BANDISK"))
  }

  func testSanitizeLabelAndWholeDiskId() {
    XCTAssertEqual(FormatPolicy.sanitizeLabel("  Data/Backup\\x  "), "DataBackupx")
    XCTAssertEqual(FormatPolicy.sanitizeLabel(""), "NTFS")
    XCTAssertEqual(FormatPolicy.wholeDiskId("disk4s2"), "disk4")
    XCTAssertEqual(FormatPolicy.wholeDiskId("disk12"), "disk12")
  }

  func testIdentityShowsSerialAndSizeAndCancelIsDefault() {
    let lines = FormatPolicy.identityLines(
      sizeLabel: "8 GB",
      deviceId: "disk4",
      serial: "ABCD-1234",
      fsHint: "ExFAT",
      mediaName: "SanDisk"
    )
    XCTAssertTrue(lines.contains("容量：8 GB"))
    XCTAssertTrue(lines.contains("设备：disk4"))
    XCTAssertTrue(lines.contains("序列号：ABCD-1234"))
    XCTAssertTrue(lines.contains("介质：SanDisk"))
    let warning = FormatPolicy.finalWarning(
      name: "BANDISK",
      sizeLabel: "8 GB",
      deviceId: "disk4",
      serial: "ABCD-1234"
    )
    XCTAssertTrue(warning.contains("BANDISK"))
    XCTAssertTrue(warning.contains("ABCD-1234"))
    XCTAssertEqual(FormatPolicy.cancelTitle, "取消")
  }
}

final class UserFacingErrorTests: XCTestCase {
  func testMapsOsascriptAndCancel() {
    XCTAssertEqual(UserFacingError.message(from: "0:205: execution error"), "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。")
    XCTAssertEqual(UserFacingError.message(from: "User canceled. (-128)"), "已取消。")
    XCTAssertEqual(UserFacingError.message(from: "bash: foo: No such file or directory (127)"), "安装助手失败，请再试一次。详情已写入日志。")
  }

  func testMapsBusyEject() {
    XCTAssertEqual(
      UserFacingError.message(from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出"),
      "磁盘正被占用：Finder。请关闭访达窗口/文件后点推出"
    )
    XCTAssertEqual(
      UserFacingError.message(from: "Unmount failed: Resource busy"),
      "磁盘正被占用：请关闭访达窗口/文件后点推出"
    )
  }
}
