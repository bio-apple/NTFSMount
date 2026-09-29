import Foundation
import NTFSMountCore
import XCTest

final class UserFacingErrorTests: XCTestCase {
  func testMapsOsascriptAndCancel() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      UserFacingError.message(from: "0:205: execution error", locale: zh),
      "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。"
    )
    XCTAssertEqual(UserFacingError.message(from: "User canceled. (-128)", locale: zh), "已取消。")
    XCTAssertEqual(UserFacingError.kind(from: "User canceled. (-60006)"), .canceled)
    XCTAssertEqual(UserFacingError.kind(from: "authorization denied (-60005)"), .adminDenied)
    XCTAssertEqual(
      UserFacingError.message(from: "authorization denied (-60005)", locale: zh),
      "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。"
    )
    XCTAssertFalse(
      UserFacingError.message(from: "authorization denied (-60005)", locale: Locale(identifier: "en"))
        .unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    )
    XCTAssertEqual(
      UserFacingError.message(from: "bash: foo: No such file or directory (127)", locale: zh),
      "找不到所需程序（可能缺少 ntfs-3g 或挂载组件）。请重新安装应用。详情已写入日志。"
    )
    XCTAssertEqual(
      UserFacingError.kind(from: "error: bundled-ntfs-3g-missing: reinstall NTFSMount.app from GitHub Latest"),
      .ntfs3gMissing
    )
    XCTAssertEqual(
      UserFacingError.message(
        from: "error: bundled-ntfs-3g-missing: reinstall NTFSMount.app from GitHub Latest",
        locale: zh
      ),
      L10n.t("runtime.ntfs3gMissing", locale: zh)
    )
    let missingEn = UserFacingError.message(
      from: "error: bundled-ntfs-3g-missing: reinstall NTFSMount.app from GitHub Latest",
      locale: Locale(identifier: "en")
    )
    XCTAssertEqual(missingEn, L10n.t("runtime.ntfs3gMissing", locale: Locale(identifier: "en")))
    XCTAssertTrue(missingEn.contains("GitHub Latest"))
    XCTAssertFalse(missingEn.contains("/opt/homebrew"))
    XCTAssertFalse(missingEn.contains("/usr/local/bin/ntfs-3g"))
    XCTAssertEqual(
      UserFacingError.kind(from: "error: 找不到捆绑的 ntfs-3g。请把 NTFSMount.app 重新装到 /Applications"),
      .ntfs3gMissing
    )
  }

  func testRawDeviceDeniedPointsAtFullDiskAccess() {
    let raw = "error: mkntfs failed: Could not open /dev/disk4s2: Operation not permitted"
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(UserFacingError.kind(from: raw), .rawDeviceDenied)
    XCTAssertEqual(UserFacingError.message(from: raw, locale: zh), L10n.t("error.rawDeviceDenied", locale: zh))
    XCTAssertFalse(
      UserFacingError.message(from: raw, locale: Locale(identifier: "en"))
        .unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    )
    // A mounted-device refusal stays a busy error, not a privacy grant problem.
    XCTAssertEqual(
      UserFacingError.kind(from: "Could not open /dev/disk4s2: Resource busy"),
      .diskBusy
    )
    // The daemon pins the app by CDHash; a replaced app gets this on every socket request and the
    // fix is the same "update the helper" flow.
    XCTAssertEqual(
      UserFacingError.kind(from: "Caller failed the signature check."),
      .helperNeedsUpdate
    )
    XCTAssertEqual(
      UserFacingError.message(from: "Caller failed the signature check.", locale: zh),
      L10n.t("error.helperNeedsUpdate", locale: zh)
    )
  }

  func testMapsBusyEject() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      UserFacingError.message(from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出", locale: zh),
      L10n.format("error.diskBusyNamed", "Finder", locale: zh)
    )
    XCTAssertEqual(
      UserFacingError.message(from: "Unmount failed: Resource busy", locale: zh),
      L10n.t("error.diskBusy", locale: zh)
    )
    XCTAssertEqual(
      UserFacingError.message(from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点卸载", locale: zh),
      L10n.format("error.diskBusyNamed", "Finder", locale: zh)
    )
    let structured = """
      busy-occupiers: Finder, TextEdit
      busy-pids: Finder[412], TextEdit[901]
      error: 磁盘正被占用：Finder, TextEdit。请关闭访达窗口/文件后点卸载
      """
    XCTAssertEqual(UserFacingError.kind(from: structured), .diskBusy)
    XCTAssertEqual(UserFacingError.occupierNames(from: structured), "Finder, TextEdit")
    XCTAssertEqual(UserFacingError.occupierPids(from: structured), "Finder[412], TextEdit[901]")
    XCTAssertEqual(
      UserFacingError.message(from: structured, locale: zh),
      L10n.format("error.diskBusyNamed", "Finder, TextEdit", locale: zh)
    )
    XCTAssertTrue(UserFacingError.message(from: structured, locale: zh).contains("Finder"))
  }

  func testBusyOccupiersTruncatesAndFdaHint() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    let many = """
      busy-occupiers: Finder, TextEdit, Preview, Terminal, Safari
      busy-pids: Finder[412], TextEdit[901], Preview[1], Terminal[2], Safari[3]
      error: Resource busy
      """
    let summary = UserFacingError.occupierSummary(
      "Finder, TextEdit, Preview, Terminal, Safari",
      locale: en
    )
    XCTAssertEqual(summary, "Finder, TextEdit, Preview, " + L10n.format("error.occupiersMore", 2, locale: en))
    XCTAssertEqual(
      UserFacingError.message(from: many, locale: en),
      L10n.format("error.diskBusyNamed", summary, locale: en)
    )
    XCTAssertTrue(UserFacingError.message(from: many, locale: en).contains("Finder"))
    XCTAssertTrue(UserFacingError.message(from: many, locale: zh).contains("Finder"))
    XCTAssertTrue(
      UserFacingError.message(from: many, locale: zh).contains(L10n.format("error.occupiersMore", 2, locale: zh))
    )

    let noFda = """
      busy-lsof-failed:
      error: Resource busy
      """
    XCTAssertEqual(UserFacingError.kind(from: noFda), .diskBusy)
    XCTAssertNil(UserFacingError.occupierNames(from: noFda))
    let fdaEn = UserFacingError.message(from: noFda, locale: en)
    XCTAssertEqual(
      fdaEn,
      L10n.t("error.diskBusy", locale: en) + "\n" + L10n.t("error.diskBusyNeedFDA", locale: en)
    )
    XCTAssertEqual(
      UserFacingError.message(from: noFda, locale: zh),
      L10n.t("error.diskBusy", locale: zh) + "\n" + L10n.t("error.diskBusyNeedFDA", locale: zh)
    )
    XCTAssertEqual(
      UserFacingError.message(from: "Unmount failed: Resource busy", locale: en),
      L10n.t("error.diskBusy", locale: en)
    )
  }

  func testOccupierLinesSurviveCleanJunkStatusPrefix() {
    let mixed = """
      clean-junk disk5s1 removed=3 failed=0
      busy-occupiers: Finder, Preview
      busy-pids: Finder[412], Preview[880]
      error: Resource busy
      """
    XCTAssertEqual(UserFacingError.kind(from: mixed), .diskBusy)
    XCTAssertEqual(UserFacingError.occupierNames(from: mixed), "Finder, Preview")
    XCTAssertEqual(UserFacingError.occupierPids(from: mixed), "Finder[412], Preview[880]")
    XCTAssertEqual(
      UserFacingError.message(from: mixed, locale: Locale(identifier: "en")),
      L10n.format("error.diskBusyNamed", "Finder, Preview", locale: Locale(identifier: "en"))
    )
  }

  func testGenericBusyHasNoOccupierNames() {
    XCTAssertNil(UserFacingError.occupierNames(from: "error: 磁盘正被占用：请关闭访达窗口/文件后点卸载"))
    XCTAssertNil(UserFacingError.occupierNames(from: "Unmount failed: Resource busy"))
  }

  func testEnglishLocaleDoesNotShowHelperChinese() {
    let en = Locale(identifier: "en")
    let busy = UserFacingError.message(
      from: "error: 磁盘正被占用：Finder。请关闭访达窗口/文件后点推出",
      locale: en
    )
    XCTAssertEqual(busy, L10n.format("error.diskBusyNamed", "Finder", locale: en))
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
    XCTAssertEqual(ja, L10n.format("error.diskBusyNamed", "Finder", locale: Locale(identifier: "ja")))
    let structuredEn = UserFacingError.message(
      from: "busy-occupiers: Finder, TextEdit\nerror: 磁盘正被占用：Finder, TextEdit。请关闭访达窗口/文件后点卸载",
      locale: en
    )
    XCTAssertEqual(
      structuredEn,
      L10n.format("error.diskBusyNamed", "Finder, TextEdit", locale: en)
    )
  }

  func testSystemDiskEjectIsNotRawEnglish() {
    let zh = Locale(identifier: "zh-Hans")
    let message = UserFacingError.message(from: "refused to eject system disk: disk4s2", locale: zh)
    XCTAssertEqual(message, L10n.t("eject.refuseSystem", locale: zh))
    XCTAssertFalse(message.contains("refused to eject"))
    XCTAssertEqual(
      UserFacingError.message(from: "refused to eject internal disk: disk0s2", locale: zh),
      L10n.t("eject.refuseSystem", locale: zh)
    )
  }
}
