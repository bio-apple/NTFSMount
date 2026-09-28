import Foundation
import NTFSMountCore
import XCTest

final class EncryptedDiskHintTests: XCTestCase {
  func testBitLockerInFSOrContentListsHintAndFormatWarning() {
    let catalog = usbCatalog(
      content: "Microsoft BitLocker",
      partInfo: [
        "FilesystemName": "BitLocker",
        "VolumeName": "SECRET",
      ]
    )

    let hints = EncryptedDiskHint.scan(using: catalog)
    XCTAssertEqual(hints.map(\.id), ["disk4s1"])
    XCTAssertFalse(hints[0].hint.isEmpty)
    XCTAssertEqual(hints[0].hint, EncryptedDiskHint.userMessage)

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk4"])
    XCTAssertEqual(disks[0].encryptionWarning, EncryptedDiskHint.userMessage)
    XCTAssertFalse((disks[0].encryptionWarning ?? "").isEmpty)
  }

  func testEncryptedTrueAndWindowsishListsHint() {
    let catalog = usbCatalog(
      content: "Microsoft Basic Data",
      partInfo: [
        "FilesystemName": "NTFS",
        "Encrypted": true,
        "VolumeName": "WIN",
      ]
    )

    let hints = EncryptedDiskHint.scan(using: catalog)
    XCTAssertEqual(hints.map(\.id), ["disk4s1"])
    XCTAssertEqual(hints[0].hint, EncryptedDiskHint.userMessage)

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks[0].encryptionWarning, EncryptedDiskHint.userMessage)
  }

  func testMicrosoftBasicDataWithUnknownFSListsHint() {
    let catalog = usbCatalog(
      content: "Microsoft Basic Data",
      partInfo: [
        "FilesystemName": "Unknown",
        "VolumeName": "DATA",
      ]
    )

    let hints = EncryptedDiskHint.scan(using: catalog)
    XCTAssertEqual(hints.map(\.id), ["disk4s1"])
    XCTAssertEqual(hints[0].hint, EncryptedDiskHint.userMessage)

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks[0].encryptionWarning, EncryptedDiskHint.userMessage)
  }

  func testKnownNTFSNotEncryptedIsNotAFalsePositive() {
    let catalog = usbCatalog(
      content: "Microsoft Basic Data",
      partInfo: [
        "FilesystemName": "NTFS",
        "Encrypted": false,
        "VolumeName": "BANDISK",
      ]
    )

    XCTAssertTrue(EncryptedDiskHint.scan(using: catalog).isEmpty)

    let disks = FormatDisk.scan(using: catalog)
    XCTAssertEqual(disks.map(\.id), ["disk4"])
    XCTAssertNil(disks[0].encryptionWarning)
  }
}

private func usbCatalog(content: String, partInfo: [String: Any]) -> MockCatalog {
  let catalog = MockCatalog()
  catalog.list = [
    "AllDisksAndPartitions": [[
      "DeviceIdentifier": "disk4",
      "Partitions": [[
        "DeviceIdentifier": "disk4s1",
        "Content": content,
      ]],
    ]],
  ]
  catalog.info["disk4"] = [
    "Internal": false,
    "TotalSize": NSNumber(value: 8_000_000_000),
    "BusProtocol": "USB",
    "MediaName": "SanDisk",
  ]
  catalog.info["disk4s1"] = partInfo
  return catalog
}
