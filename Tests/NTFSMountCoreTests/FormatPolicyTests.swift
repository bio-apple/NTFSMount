import Foundation
import NTFSMountCore
import XCTest

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
    XCTAssertTrue(
      ForceUnmountCopy.body(volumeName: "DATA", occupiers: "Finder[412]", locale: zh).contains("Finder[412]")
    )
    XCTAssertTrue(
      ForceUnmountCopy.body(volumeName: "DATA", occupiers: "Finder[412]", locale: Locale(identifier: "en"))
        .contains("Finder[412]")
    )
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
