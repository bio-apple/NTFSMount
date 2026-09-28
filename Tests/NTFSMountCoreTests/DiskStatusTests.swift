import Foundation
import NTFSMountCore
import XCTest

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
