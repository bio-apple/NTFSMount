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
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("classify: volume may be corrupted"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("NTFS volume may be corrupted"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: Windows is hibernated"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: dirty/hibernation"))
  }

  func testPreMountProbeClassificationAndCopy() {
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume is clean"), .healthy)
    XCTAssertEqual(VolumeHealth.probeKind(from: "NTFS partition processed successfully."), .healthy)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume is dirty"), .dirty)
    XCTAssertEqual(VolumeHealth.probeKind(from: "The disk contains an unclean file system"), .dirty)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: Windows is hibernated"), .hibernated)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume may be corrupted"), .corrupt)
    XCTAssertEqual(VolumeHealth.probeKind(from: "NTFS volume may be corrupted"), .corrupt)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: unknown"), .unknown)
    XCTAssertEqual(VolumeHealth.probeKind(from: "Mounted successfully"), .unknown)
    XCTAssertEqual(
      VolumeHealth.probeKind(from: "unclean file system. NTFS partition was processed successfully."),
      .dirty
    )
    XCTAssertEqual(
      VolumeHealth.probeKind(from: "Volume is dirty. Windows is hibernated."),
      .hibernated
    )

    XCTAssertNil(VolumeHealth.preMountDialog(for: .healthy))
    XCTAssertNil(VolumeHealth.preMountDialog(for: .unknown))
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .dirty), .dirtyOrCorrupt)
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .corrupt), .dirtyOrCorrupt)
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .hibernated), .hibernated)

    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(VolumeHealth.PreMountCopy.dirtyTitle(locale: zh), "NTFS 卷可能已损坏/未正常卸载")
    XCTAssertEqual(VolumeHealth.PreMountCopy.readOnlyTitle(locale: zh), "以只读挂载")
    XCTAssertEqual(VolumeHealth.PreMountCopy.fixThenWritableTitle(locale: zh), "尝试修复后可写")
    XCTAssertEqual(VolumeHealth.PreMountCopy.cancelTitle(locale: zh), "取消")
    XCTAssertEqual(VolumeHealth.PreMountCopy.hiberTitle(locale: zh), "检测到 Windows 休眠")
    let dirtyBody = VolumeHealth.PreMountCopy.dirtyBody(volumeName: "BANDISK", locale: zh)
    XCTAssertTrue(dirtyBody.contains("BANDISK"))
    XCTAssertTrue(dirtyBody.contains("未正常卸载") || dirtyBody.contains("损坏"))
    XCTAssertTrue(dirtyBody.contains("ntfsfix"))
    XCTAssertFalse(dirtyBody.contains("repairVolume"))
    let hiberBody = VolumeHealth.PreMountCopy.hiberBody(volumeName: "WIN", locale: zh)
    XCTAssertTrue(hiberBody.contains("WIN"))
    XCTAssertTrue(hiberBody.contains("彻底关机"))
    XCTAssertTrue(hiberBody.contains("只读"))
    XCTAssertTrue(hiberBody.contains("不会运行 ntfsfix"))
    XCTAssertFalse(hiberBody.contains("尝试修复后可写"))
  }

  func testKextBlockIsClassified() {
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("FSKit module is disabled"))
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("kernel extension denied"))
    XCTAssertEqual(VolumeHealth.advice(for: "fskit unavailable", success: false), .failedKext)
  }

  func testReadOnlyStatusExplainsCause() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      VolumeHealth.shortStatus(
        busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: nil, locale: zh
      ),
      "只读 · 系统 NTFS"
    )
    XCTAssertEqual(
      VolumeHealth.shortStatus(
        busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty, locale: zh
      ),
      "只读 · 休眠/未正常关机"
    )
    XCTAssertTrue(
      VolumeHealth.detailStatus(
        isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty, locale: zh
      )
      .contains("彻底关机")
    )
  }

  func testJournalLabelStaysUnknownUntilProbeAndNeverYesNo() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      VolumeHealth.journalLabel(probeKind: nil, lastAdvice: nil, helperText: "", locale: zh),
      "未知"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: nil, lastAdvice: .writable, helperText: "OK\nrw\n", locale: zh
      ),
      "未知"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .dirty, lastAdvice: .readOnlyDirty, helperText: "classify: volume is dirty", locale: zh
      ),
      "脏卷"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .hibernated, lastAdvice: .readOnlyDirty,
        helperText: "classify: Windows is hibernated", locale: zh
      ),
      "休眠"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .healthy, lastAdvice: .writable, helperText: "classify: volume is clean", locale: zh
      ),
      "未见脏卷标记"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: nil, lastAdvice: .readOnlyDirty, helperText: "Windows is hibernated", locale: zh
      ),
      "休眠"
    )
    let fallback = VolumeHealth.journalLabel(
      probeKind: .unknown, lastAdvice: .readOnlyDirty, helperText: "", locale: zh
    )
    XCTAssertEqual(fallback, "只读 · 休眠/未正常关机")
    XCTAssertFalse(fallback == "Yes" || fallback == "No")
  }
}

final class AutoMountPolicyTests: XCTestCase {
  func testUnmountedExternalIsEligiblePerVolumeNotOnlyFirst() {
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      ),
      "second unmounted volume stays eligible independently of volumes.first"
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: true, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: true, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: true, alreadyAttempted: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: true
      )
    )
  }

  func testHelperMountsUnmountedExternalWithoutRequiringStillMounted() {
    XCTAssertTrue(
      AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: false, isWritable: false),
      "unmounted external NTFS must auto-mount; do not require volume_still_mounted"
    )
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: true, isOurFuse: false, isWritable: false))
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: true, isWritable: false))
    XCTAssertFalse(AutoMountPolicy.helperShouldMount(isInternal: false, isOurFuse: false, isWritable: true))
  }

  func testRecordAttemptOnlyAfterRefuseOrHelperReturn() {
    XCTAssertFalse(AutoMountPolicy.shouldRecordAttempt(userRefused: false, helperReturned: false))
    XCTAssertTrue(AutoMountPolicy.shouldRecordAttempt(userRefused: true, helperReturned: false))
    XCTAssertTrue(AutoMountPolicy.shouldRecordAttempt(userRefused: false, helperReturned: true))
  }

  func testToggleStaysOffUntilHelperLegalAndWritableStamp() {
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: false, legalAccepted: true, writableStampPresent: true, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: false, writableStampPresent: true, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: false, userOptedOff: false
      )
    )
    XCTAssertFalse(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: true, userOptedOff: true
      )
    )
    XCTAssertTrue(
      AutoMountPolicy.shouldAutoEnable(
        helperInstalled: true, legalAccepted: true, writableStampPresent: true, userOptedOff: false
      )
    )
  }

  func testWritableAutoMountSkippedWhenDirtyCorruptOrHiber() {
    XCTAssertTrue(AutoMountPolicy.allowsWritableAttempt(.healthy))
    XCTAssertTrue(AutoMountPolicy.allowsWritableAttempt(.unknown))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.dirty))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.corrupt))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.hibernated))
  }

  func testMayAttemptRequiresLegalConsentEvenIfToggleOn() {
    XCTAssertFalse(
      AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: true, legalAccepted: false),
      "refresh/DiskWatch must not auto-mount before the legal dialog"
    )
    XCTAssertFalse(AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: false, legalAccepted: true))
    XCTAssertFalse(AutoMountPolicy.mayAttempt(autoMountEnabled: false, helperReady: true, legalAccepted: true))
    XCTAssertTrue(AutoMountPolicy.mayAttempt(autoMountEnabled: true, helperReady: true, legalAccepted: true))
  }

  func testQueueUsesAllowsWritableAttemptForKnownDirtyProbe() {
    XCTAssertTrue(
      AutoMountPolicy.isEligible(
        isInternal: false, isWritableFuse: false, userSkippedUnmount: false, alreadyAttempted: false
      )
    )
    XCTAssertTrue(AutoMountPolicy.allowsWritableAttempt(.unknown), "first insert with no probe still queues; helper then RW or RO")
    XCTAssertFalse(
      AutoMountPolicy.allowsWritableAttempt(.dirty),
      "known dirty/hiber/corrupt must not be queued for RW auto-mount"
    )
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.hibernated))
    XCTAssertFalse(AutoMountPolicy.allowsWritableAttempt(.corrupt))
  }
}

final class OnboardingCopyTests: XCTestCase {
  func testAgreeIsPrimaryAndBodyMentionsHelper() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(OnboardingCopy.quitTitle(locale: zh), "退出")
    XCTAssertEqual(OnboardingCopy.agreeTitle(locale: zh), "同意并继续")
    let body = OnboardingCopy.body(notarized: false, locale: zh)
    XCTAssertTrue(body.contains("管理员密码"))
    XCTAssertTrue(body.contains("go-nfsv4"))
    XCTAssertTrue(body.contains("回车即同意"))
    XCTAssertTrue(body.contains("安装"))
    XCTAssertEqual(OnboardingCopy.copyVersion, 6)
    XCTAssertFalse(UpdateCopy.feedURL.lowercased().contains("latest"))
    XCTAssertTrue(UpdateCopy.feedURL.contains("v1.2.0/appcast.xml"))
    XCTAssertFalse(OnboardingCopy.body(notarized: false, locale: zh).contains("检查更新"))
    XCTAssertFalse(OnboardingCopy.body(notarized: false, locale: zh).contains("v1.2.0"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("GitHub Releases"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("当前构建未公证"))
    XCTAssertTrue(OnboardingCopy.gatekeeperBody(locale: zh).contains("仍要打开"))
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
    let zh = Locale(identifier: "zh-Hans")
    let lines = FormatPolicy.identityLines(
      sizeLabel: "8 GB",
      deviceId: "disk4",
      serial: "ABCD-1234",
      fsHint: "ExFAT",
      mediaName: "SanDisk",
      locale: zh
    )
    XCTAssertTrue(lines.contains("容量：8 GB"))
    XCTAssertTrue(lines.contains("设备：disk4"))
    XCTAssertTrue(lines.contains("序列号：ABCD-1234"))
    XCTAssertTrue(lines.contains("介质：SanDisk"))
    let warning = FormatPolicy.finalWarning(
      name: "BANDISK",
      sizeLabel: "8 GB",
      deviceId: "disk4",
      serial: "ABCD-1234",
      locale: zh
    )
    XCTAssertTrue(warning.contains("BANDISK"))
    XCTAssertTrue(warning.contains("ABCD-1234"))
    XCTAssertEqual(FormatPolicy.cancelTitle(locale: zh), "取消")
    XCTAssertEqual(AlertDefaultPolicy.format, .cancelDefault)
    XCTAssertEqual(AlertDefaultPolicy.format.keyEquivalent(at: 0, buttonCount: 2), "\r")
    XCTAssertEqual(AlertDefaultPolicy.format.keyEquivalent(at: 1, buttonCount: 2), "")
  }

  func testFormatNtfsfixWritableAndForceUnmountAreCancelDefault() {
    let policies = [
      AlertDefaultPolicy.format,
      AlertDefaultPolicy.ntfsfix,
      AlertDefaultPolicy.writableConfirm,
      AlertDefaultPolicy.forceUnmount,
      AlertDefaultPolicy.repairMount,
    ]
    for policy in policies {
      XCTAssertEqual(policy, .cancelDefault)
      XCTAssertEqual(policy.keyEquivalent(at: 0, buttonCount: 2), "\r")
      XCTAssertEqual(policy.keyEquivalent(at: 1, buttonCount: 2), "")
    }
  }

  func testForceUnmountCopyKeepsVolumeNameAndCancelDefault() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(ForceUnmountCopy.title(volumeName: "My Passport", locale: zh), "强制卸载「My Passport」？")
    XCTAssertTrue(ForceUnmountCopy.body(volumeName: "移动硬盘", locale: zh).contains("移动硬盘"))
    XCTAssertEqual(ForceUnmountCopy.forceTitle(locale: zh), "强制卸载")
    XCTAssertEqual(AlertDefaultPolicy.forceUnmount, .cancelDefault)
  }

  func testRepairMountCopyIsLocalizedAndCancelDefault() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(AlertDefaultPolicy.repairMount, .cancelDefault)
    XCTAssertEqual(RepairMountCopy.title(locale: en), "Repair Mount Environment?")
    XCTAssertEqual(RepairMountCopy.title(locale: zh), "修复挂载环境？")
    XCTAssertEqual(RepairMountCopy.actionTitle(locale: en), "Repair")
    XCTAssertEqual(RepairMountCopy.actionTitle(locale: zh), "修复")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: en), "Repair Mount Environment…")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: zh), "修复挂载环境…")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: Locale(identifier: "zh-Hant")), "修復掛載環境…")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: Locale(identifier: "ja")), "マウント環境を修復…")
    let enBody = RepairMountCopy.body(locale: en)
    XCTAssertTrue(enBody.contains("unmount leftover"))
    XCTAssertTrue(enBody.contains("ntfs-3g"))
    XCTAssertFalse(enBody.contains("修复"))
    XCTAssertFalse(enBody.contains("卸载"))
    XCTAssertFalse(enBody.contains("pfctl"))
    XCTAssertFalse(RepairMountCopy.body(locale: zh).contains("pfctl"))
    XCTAssertFalse(RepairMountCopy.body(locale: zh).contains("vmnet"))
    XCTAssertEqual(
      RepairMountCopy.parseCounts("ok repair-env unmounted=2 killed=1 busy=0")?.unmounted,
      2
    )
    XCTAssertEqual(
      RepairMountCopy.summary(unmounted: 2, killed: 1, busy: 0, locale: en),
      "Unmounted 2 leftover mount(s) and stopped 1 leftover process(es)."
    )
    XCTAssertEqual(
      RepairMountCopy.summary(unmounted: 1, killed: 0, busy: 1, locale: zh).contains("未强制卸载"),
      true
    )
    let enMsg = RepairMountCopy.userMessage(
      helperText: "ok repair-env unmounted=0 killed=0 busy=0",
      helperOK: true,
      helperRestarted: true,
      locale: en
    )
    XCTAssertTrue(enMsg.contains("No leftover"))
    XCTAssertTrue(enMsg.contains("Mount helper restarted"))
    XCTAssertFalse(enMsg.contains("没有"))
    let failed = RepairMountCopy.userMessage(
      helperText: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点卸载",
      helperOK: false,
      helperRestarted: false,
      locale: en
    )
    XCTAssertEqual(failed, "Could not repair the mount environment.")
    XCTAssertFalse(failed.contains("磁盘"))
  }
}

final class UserFacingErrorTests: XCTestCase {
  func testMapsOsascriptAndCancel() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      UserFacingError.message(from: "0:205: execution error", locale: zh),
      "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。"
    )
    XCTAssertEqual(UserFacingError.message(from: "User canceled. (-128)", locale: zh), "已取消。")
    XCTAssertEqual(
      UserFacingError.message(from: "bash: foo: No such file or directory (127)", locale: zh),
      "找不到所需程序（可能缺少 ntfs-3g 或挂载组件）。请重新安装应用。详情已写入日志。"
    )
  }

  func testMapsBusyEject() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      UserFacingError.message(from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出", locale: zh),
      "磁盘正被占用：Finder。请关闭访达窗口/文件后点推出"
    )
    XCTAssertEqual(
      UserFacingError.message(from: "Unmount failed: Resource busy", locale: zh),
      "磁盘正被占用：请关闭访达窗口/文件后点推出"
    )
    XCTAssertEqual(
      UserFacingError.message(from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点卸载", locale: zh),
      "磁盘正被占用：Finder。请关闭访达窗口/文件后点卸载"
    )
  }

  func testEnglishLocaleDoesNotShowHelperChinese() {
    let en = Locale(identifier: "en")
    let busy = UserFacingError.message(
      from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出",
      locale: en
    )
    XCTAssertEqual(busy, L10n.t("error.diskBusy", locale: en))
    XCTAssertFalse(busy.contains("磁盘"))
    XCTAssertFalse(busy.contains("访达"))
    let other = UserFacingError.message(from: "挂载失败：磁盘 dirty 或 Windows 休眠", locale: en)
    XCTAssertFalse(other.contains("挂载"))
    XCTAssertFalse(other.contains("磁盘"))
    let ja = UserFacingError.message(
      from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出",
      locale: Locale(identifier: "ja")
    )
    XCTAssertFalse(ja.contains("磁盘"))
    XCTAssertEqual(ja, L10n.t("error.diskBusy", locale: Locale(identifier: "ja")))
  }
}

final class L10nTests: XCTestCase {
  func testLanguageMatchingAndFallback() {
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "en")), "en")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "en_US")), "en")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "en-GB")), "en")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "zh-Hans")), "zh-Hans")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "zh-CN")), "zh-Hans")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "zh-Hant")), "zh-Hant")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "zh-TW")), "zh-Hant")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "zh-HK")), "zh-Hant")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "ja")), "ja")
    XCTAssertEqual(L10n.languageCode(for: Locale(identifier: "fr")), "zh-Hans")
  }

  func testEnglishAndChineseCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(OnboardingCopy.agreeTitle(locale: en), "Agree and Continue")
    XCTAssertEqual(OnboardingCopy.agreeTitle(locale: zh), "同意并继续")
    XCTAssertEqual(L10n.t("menu.diagnose", locale: en), "Diagnose Environment…")
    XCTAssertEqual(L10n.t("menu.diagnose", locale: zh), "诊断环境…")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: en), "Repair Mount Environment…")
    XCTAssertEqual(L10n.t("menu.repairEnv", locale: zh), "修复挂载环境…")
    XCTAssertEqual(
      L10n.t("diagnose.checking", locale: en),
      "Checking bundled components and helper…"
    )
    XCTAssertEqual(L10n.t("diagnose.checking", locale: zh), "正在检查捆绑组件与挂载助手…")
    XCTAssertEqual(L10n.t("diagnose.installHelper", locale: zh), "安装挂载助手…")
    XCTAssertEqual(L10n.t("diagnose.installFailed", locale: zh), "安装挂载助手失败")
    XCTAssertTrue(L10n.t("privileged.socketMissing", locale: zh).contains("socket"))
    XCTAssertEqual(L10n.t("window.firstInstall", locale: zh), "助手未安装（socket 不存在）。")
    XCTAssertTrue(L10n.t("window.helperMissingDetail", locale: zh).contains("管理员密码"))
    XCTAssertFalse(L10n.t("diagnose.brokenBundle", locale: en).contains("brew install macfuse"))
    XCTAssertTrue(L10n.t("diagnose.brokenBundle", locale: zh).contains("重新下载"))
    XCTAssertEqual(
      L10n.t("window.emptyHint", locale: en),
      "Closing this window keeps the menu-bar NTFS icon. Use Eject to remove a disk. Do not Quit from the Dock if you want the icon to stay."
    )
    XCTAssertFalse(L10n.t("settings.autoMountNote", locale: en).contains("Issue"))
    XCTAssertTrue(L10n.t("settings.autoMountNote", locale: zh).contains("只读"))
    XCTAssertTrue(L10n.t("settings.autoMountNote", locale: zh).contains("关闭"))
    XCTAssertTrue(L10n.t("settings.autoMountNeedHelper", locale: zh).contains("助手"))
    XCTAssertTrue(L10n.t("settings.autoMountNeedHelper", locale: en).contains("helper"))
    XCTAssertFalse(L10n.t("settings.autoMountNote", locale: en).contains("只读"))
    XCTAssertFalse(L10n.t("settings.autoMountNeedHelper", locale: en).contains("助手"))
    XCTAssertNotEqual(
      L10n.t("settings.autoMount", locale: en),
      L10n.t("settings.autoMount", locale: zh)
    )
    XCTAssertTrue(L10n.t("settings.autoMountNote", locale: Locale(identifier: "zh-Hant")).contains("關閉"))
    XCTAssertTrue(L10n.t("settings.autoMountNeedHelper", locale: Locale(identifier: "ja")).contains("ヘルパー"))
    XCTAssertFalse(L10n.t("helper.privilegeHint", locale: zh).contains("CDHash"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("EdDSA"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("v1.2.0"))
    XCTAssertTrue(L10n.t("update.autoCheckNote", locale: en).contains("GitHub Releases"))
    XCTAssertTrue(L10n.t("update.autoCheckNote", locale: zh).contains("GitHub Releases"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("Check for Updates"))
    XCTAssertEqual(L10n.t("window.usageAfterMount", locale: Locale(identifier: "zh-Hant")), "掛載後可見")
    XCTAssertEqual(L10n.t("settings.advanced", locale: Locale(identifier: "ja")), "詳細")
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: en).contains("Return means you agree"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("回车即同意"))
    XCTAssertEqual(L10n.t("diskStatus.encryptionHint", locale: zh), "可能加密")
    XCTAssertEqual(L10n.t("diskStatus.encryptionNone", locale: zh), "未见加密线索")
    XCTAssertEqual(L10n.t("diskStatus.journalUnknown", locale: zh), "未知")
    XCTAssertEqual(L10n.t("diskStatus.mountRW", locale: en), "Read/Write")
    XCTAssertEqual(ForceUnmountCopy.forceTitle(locale: zh), "强制卸载")
    XCTAssertFalse(L10n.t("format.confirmExtra", locale: en).contains("格式化"))
    XCTAssertTrue(L10n.format("format.confirmExtra", "BANDISK", locale: en).contains("BANDISK"))
    XCTAssertFalse(ForceUnmountCopy.body(volumeName: "X", locale: en).contains("强制"))
    XCTAssertFalse(L10n.t("repairEnv.title", locale: en).contains("修复"))
    XCTAssertFalse(L10n.t("diskStatus.encryptionHint", locale: en).contains("加密"))
    XCTAssertEqual(L10n.format("about.version", "1.0.0", locale: en), "Version 1.0.0")
    XCTAssertEqual(L10n.format("about.version", "1.0.0", locale: zh), "版本 1.0.0")
    XCTAssertEqual(
      L10n.format("about.version", "1.0.0", locale: Locale(identifier: "zh-Hant")),
      "版本 1.0.0"
    )
    XCTAssertEqual(
      L10n.format("about.version", "1.0.0", locale: Locale(identifier: "ja")),
      "バージョン 1.0.0"
    )
    XCTAssertEqual(AppVersion.line(version: "1.0.0", locale: en), "Version 1.0.0")
    XCTAssertEqual(AppVersion.menuTitle(version: "1.0.0", locale: en), "About 1.0.0")
    XCTAssertEqual(AppVersion.menuTitle(version: "1.0.0", locale: zh), "关于 1.0.0")
    XCTAssertFalse(AppVersion.line(version: "1.0.0", locale: en).contains("版本"))
    XCTAssertFalse(AppVersion.menuTitle(version: "1.0.0", locale: en).contains("关于"))
    XCTAssertEqual(L10n.t("__missing.l10n.key__", locale: en), "__missing.l10n.key__")
  }

  func testEnglishCatalogHasNoHan() {
    let en = Locale(identifier: "en")
    let keys = [
      "format.confirmExtra", "format.confirmTitle", "forceUnmount.title", "forceUnmount.body",
      "forceUnmount.action", "repairEnv.title", "repairEnv.body", "repairEnv.action",
      "repairEnv.working", "repairEnv.summary", "repairEnv.summaryBusy", "repairEnv.summaryNone",
      "repairEnv.helperRestarted", "repairEnv.failed", "menu.repairEnv",
      "diskStatus.mountMode", "diskStatus.mountRW", "diskStatus.mountRO", "diskStatus.used",
      "diskStatus.encryption", "diskStatus.encryptionHint", "diskStatus.encryptionNone",
      "diskStatus.journal", "diskStatus.journalUnknown", "diskStatus.journalDirty",
      "diskStatus.journalHibernated", "diskStatus.journalCorrupt", "diskStatus.journalClean",
      "settings.autoMount", "settings.autoMountNote", "settings.autoMountNeedHelper",
      "dirty.title", "dirty.body", "premount.dirtyTitle", "premount.hiberTitle",
      "status.roDirty", "error.diskBusy", "window.usageAfterMount",
      "about.version", "menu.about",
    ]
    let han = try! NSRegularExpression(pattern: "\\p{Han}")
    for key in keys {
      let value = L10n.t(key, locale: en)
      XCTAssertNotEqual(value, key, "missing en catalog entry: \(key)")
      let range = NSRange(value.startIndex..., in: value)
      XCTAssertNil(han.firstMatch(in: value, range: range), "en \(key) contains CJK: \(value)")
    }
  }
}

final class HelperIpcTests: XCTestCase {
  func testV2RoundTripKeepsNewlinesInVolumeLabel() {
    let args = ["format", "disk4s1", "Win\nData"]
    guard let data = HelperIpc.encodeV2(args) else {
      return XCTFail("encode")
    }
    XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("v1 ") == true)
    XCTAssertEqual(HelperIpc.decodeV2(data), args)
  }

  func testV2RoundTripKeepsForceFlagAndSpacedCJKLabels() {
    let unmount = ["unmount", "disk5s1", "force"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(unmount)!), unmount)
    let passport = ["format", "disk4", "My Passport"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(passport)!), passport)
    let cjk = ["format", "disk4", "移动硬盘"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(cjk)!), cjk)
  }

  func testV2RejectsTooManyArgs() {
    let args = Array(repeating: "x", count: HelperIpc.maxArgs + 1)
    XCTAssertNil(HelperIpc.encodeV2(args))
  }

  func testV1CompatStillStripsNewlines() {
    let data = HelperIpc.encodeV1Compat(["format", "disk4s1", "A\nB"])
    let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
    XCTAssertTrue(text.hasPrefix("v1 3\n"))
    XCTAssertTrue(text.contains("A B\n"))
    XCTAssertFalse(text.contains("A\nB"))
  }

  func testHeartbeatNULsAreStrippedBeforeOK() {
    var data = Data([0, 0])
    data.append(contentsOf: Array("OK\nrw\n".utf8))
    data.append(0)
    let text = String(data: HelperIpc.stripHeartbeats(data), encoding: .utf8)
    XCTAssertEqual(text, "OK\nrw\n")
  }

  func testFormatUsesTenMinuteRecvTimeout() {
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "format"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "fix"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "ntfsfix"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "mount"), 180)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "probe"), 180)
  }
}

final class MenuBarTooltipTests: XCTestCase {
  func testCardMatchesMenuBarMockup() {
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 931_000_000_000,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 512_000_000_000,
      freeBytes: 419_000_000_000
    )
    let lines = MenuBarTooltip.card(vol, locale: Locale(identifier: "en"))
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(lines[0], "Samsung T7")
    XCTAssertEqual(lines[1], "NTFS • RW")
    XCTAssertEqual(lines[2], "disk4s1")
    XCTAssertTrue(lines[3].contains(" / "))
  }

  func testCardFallsBackToVolumeNameWhenMediaNameMissing() {
    let vol = NTFSVolume(
      id: "disk5s1",
      name: "WINDATA",
      size: 8_000_000_000,
      mountPoint: "",
      isWritableFuse: false,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "",
      usedBytes: 0,
      freeBytes: 0
    )
    let card = MenuBarTooltip.card(vol, locale: Locale(identifier: "en"))
    XCTAssertTrue(card.hasPrefix("WINDATA\n"))
    XCTAssertTrue(card.contains("NTFS • —"))
    XCTAssertTrue(card.contains("disk5s1"))
  }

  func testExtraJoinsCardsAndEmptyUsesNoNTFSCopy() {
    let empty = MenuBarTooltip.extra([], locale: Locale(identifier: "en"))
    XCTAssertEqual(empty, L10n.t("menu.noNTFS", locale: Locale(identifier: "en")))
    let a = NTFSVolume(
      id: "disk4s1",
      name: "A",
      size: 1,
      mountPoint: "",
      isWritableFuse: false,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Drive A",
      usedBytes: 0,
      freeBytes: 0
    )
    let b = NTFSVolume(
      id: "disk5s1",
      name: "B",
      size: 1,
      mountPoint: "/Volumes/B",
      isWritableFuse: false,
      isReadOnlyMounted: true,
      isInternal: false,
      mediaName: "Drive B",
      usedBytes: 0,
      freeBytes: 0
    )
    let extra = MenuBarTooltip.extra([a, b], locale: Locale(identifier: "en"))
    XCTAssertTrue(extra.contains("Drive A"))
    XCTAssertTrue(extra.contains("Drive B"))
    XCTAssertTrue(extra.contains("NTFS • RO"))
    XCTAssertTrue(extra.contains("\n\n"))
  }

  func testZhHansUsesWritableMark() {
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 1,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 1,
      freeBytes: 1
    )
    let card = MenuBarTooltip.card(vol, locale: Locale(identifier: "zh-Hans"))
    XCTAssertTrue(card.contains("NTFS • 可写"))
  }
}

final class DiskStatusTests: XCTestCase {
  func testRowsAreHonestAndCompact() {
    let zh = Locale(identifier: "zh-Hans")
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 931_000_000_000,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 412_000_000_000,
      freeBytes: 519_000_000_000
    )
    let rows = DiskStatus.rows(volume: vol, locale: zh)
    XCTAssertEqual(rows.map(\.label), ["文件系统", "挂载模式", "容量", "已用", "BitLocker", "脏日志"])
    XCTAssertEqual(rows[0].value, "NTFS")
    XCTAssertEqual(rows[1].value, "可读写")
    XCTAssertEqual(rows[2].value, vol.sizeLabel)
    XCTAssertEqual(rows[3].value, ByteCountFormatter.string(fromByteCount: 412_000_000_000, countStyle: .file))
    XCTAssertEqual(rows[4].value, "未见加密线索")
    XCTAssertEqual(rows[5].value, "未知")
    XCTAssertFalse(rows.contains { $0.value == "Locked" || $0.value == "Unlocked" })
    XCTAssertFalse(rows.contains { $0.value == "Yes" || $0.value == "No" })

    let hinted = DiskStatus.rows(volume: vol, hasEncryptionHint: true, locale: zh)
    XCTAssertEqual(hinted[4].value, "可能加密")

    let dirty = DiskStatus.rows(
      volume: vol,
      probeKind: .dirty,
      lastAdvice: .readOnlyDirty,
      helperText: "classify: volume is dirty",
      locale: zh
    )
    XCTAssertEqual(dirty[5].value, "脏卷")

    let en = DiskStatus.rows(volume: vol, locale: Locale(identifier: "en"))
    XCTAssertEqual(en[1].value, "Read/Write")
    XCTAssertEqual(en[4].value, "No encryption hint")
    XCTAssertEqual(en[5].value, "Unknown")
  }

  func testUsedWaitsUntilMountWhenBytesUnknown() {
    let vol = NTFSVolume(
      id: "disk5s1",
      name: "WINDATA",
      size: 8_000_000_000,
      mountPoint: "",
      isWritableFuse: false,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "",
      usedBytes: 0,
      freeBytes: 0
    )
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(DiskStatus.mountMode(vol, locale: zh), "未挂载")
    XCTAssertEqual(DiskStatus.usedValue(vol, locale: zh), "挂载后可见")
    XCTAssertEqual(
      DiskStatus.encryptionValue(hasHint: false, locale: zh),
      "未见加密线索"
    )
  }
}

