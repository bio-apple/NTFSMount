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
}
