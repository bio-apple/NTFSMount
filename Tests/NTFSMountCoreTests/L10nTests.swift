import Foundation
import NTFSMountCore
import XCTest

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

  func testDiagnoseAndWindowCatalogs() {
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
    XCTAssertEqual(L10n.t("diagnose.export", locale: en), "Export Diagnostic Report")
    XCTAssertEqual(L10n.t("diagnose.export", locale: zh), "导出诊断报告")
    XCTAssertEqual(L10n.t("menu.exportDiagnose", locale: zh), "导出诊断报告…")
    XCTAssertTrue(L10n.t("privileged.socketMissing", locale: zh).contains("socket"))
    XCTAssertEqual(L10n.t("window.firstInstall", locale: zh), "助手未安装（socket 不存在）。")
    XCTAssertTrue(L10n.t("window.helperMissingDetail", locale: zh).contains("管理员密码"))
    XCTAssertFalse(L10n.t("diagnose.brokenBundle", locale: en).contains("brew install macfuse"))
    XCTAssertFalse(L10n.t("diagnose.brokenBundle", locale: en).contains("brew install ntfs-3g"))
    XCTAssertTrue(L10n.t("diagnose.brokenBundle", locale: zh).contains("GitHub Latest"))
    XCTAssertTrue(L10n.t("runtime.ntfs3gMissing", locale: en).contains("GitHub Latest"))
    XCTAssertFalse(L10n.t("runtime.ntfs3gMissing", locale: en).contains("brew install"))
    XCTAssertFalse(L10n.t("runtime.ntfs3gMissing", locale: en).contains("/opt/homebrew"))
    XCTAssertTrue(L10n.t("runtime.ntfs3gMissing", locale: zh).contains("GitHub Latest"))
    XCTAssertEqual(
      L10n.t("window.emptyHint", locale: en),
      "Closing this window keeps the menu-bar NTFS icon. Use Eject to remove a disk. "
        + "Do not Quit from the Dock if you want the icon to stay."
    )
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: en).contains("Return means you agree"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("回车即同意"))
  }

  func testSettingsAndHelperCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
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
    XCTAssertTrue(L10n.t("helper.privilegeHint", locale: en).contains("SIP"))
    XCTAssertTrue(L10n.t("helper.privilegeHint", locale: en).contains("Authorization"))
    XCTAssertFalse(L10n.t("helper.privilegeHint", locale: en).contains("关闭"))
    XCTAssertTrue(L10n.t("helper.hintAdHoc", locale: en).contains("Authorization"))
    XCTAssertTrue(L10n.t("helper.hintAdHoc", locale: en).contains("SIP"))
    XCTAssertEqual(
      L10n.t("privileged.authUnavailable", locale: en),
      "Authorization Services could not start a privileged installer. SIP stays enabled. "
        + "Use a Developer ID / notarized build that can register SMAppService, or try again."
    )
    XCTAssertFalse(L10n.t("privileged.authUnavailable", locale: en).contains("关闭"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("EdDSA"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("v1.2.0"))
    XCTAssertTrue(L10n.t("update.autoCheckNote", locale: en).contains("GitHub Releases"))
    XCTAssertTrue(L10n.t("update.autoCheckNote", locale: zh).contains("GitHub Releases"))
    XCTAssertFalse(L10n.t("update.autoCheckNote", locale: en).contains("Check for Updates"))
    XCTAssertEqual(L10n.t("window.usageAfterMount", locale: Locale(identifier: "zh-Hant")), "掛載後可見")
    XCTAssertEqual(L10n.t("settings.advanced", locale: Locale(identifier: "ja")), "詳細")
  }

  func testCleanMacJunkCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    let hant = Locale(identifier: "zh-Hant")
    let ja = Locale(identifier: "ja")
    let keys = [
      "settings.cleanMacJunk", "settings.cleanMacJunkNote",
      "cleanJunk.working", "cleanJunk.done", "cleanJunk.failedTitle",
      "cleanJunk.failedBody", "cleanJunk.continueWithout",
    ]
    for key in keys {
      XCTAssertNotEqual(L10n.t(key, locale: en), key, "missing en \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: zh), key, "missing zh-Hans \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: hant), key, "missing zh-Hant \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: ja), key, "missing ja \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: en), L10n.t(key, locale: zh))
    }
    XCTAssertEqual(L10n.t("settings.cleanMacJunk", locale: en), "Clean Mac junk files before eject")
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: en).contains(".DS_Store"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: en).contains("._*"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: en).contains(".Trashes"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: en).contains(".Spotlight-V100"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: en).contains("Off by default"))
    XCTAssertFalse(L10n.t("settings.cleanMacJunkNote", locale: en).contains("清理"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunk", locale: zh).contains("推出前"))
    XCTAssertTrue(L10n.t("settings.cleanMacJunkNote", locale: hant).contains("預設關閉"))
    XCTAssertTrue(L10n.t("cleanJunk.continueWithout", locale: ja).contains("続ける"))
  }

  func testBusyOccupierCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    let hant = Locale(identifier: "zh-Hant")
    let ja = Locale(identifier: "ja")
    for key in ["error.diskBusyNamed", "error.occupiersMore", "error.diskBusyNeedFDA", "error.diskBusy"] {
      XCTAssertNotEqual(L10n.t(key, locale: en), key, "missing en \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: zh), key, "missing zh-Hans \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: hant), key, "missing zh-Hant \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: ja), key, "missing ja \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: en), L10n.t(key, locale: zh))
    }
    XCTAssertEqual(
      L10n.format("error.diskBusyNamed", "Finder", locale: en),
      "The disk is in use by Finder. Close those programs, then retry."
    )
    XCTAssertEqual(
      L10n.format("error.diskBusyNamed", "Finder", locale: zh),
      "磁盘正被占用：Finder。请关闭这些程序后重试。"
    )
    XCTAssertEqual(L10n.format("error.occupiersMore", 2, locale: en), "and 2 more")
    XCTAssertEqual(L10n.format("error.occupiersMore", 2, locale: zh), "等 2 个")
    XCTAssertEqual(
      L10n.t("error.diskBusyNeedFDA", locale: en),
      "Grant Full Disk Access to see which app is using the disk."
    )
    XCTAssertEqual(
      L10n.t("error.diskBusyNeedFDA", locale: zh),
      "请授予完全磁盘访问权限以查看是哪个应用占用。"
    )
  }

  func testFullDiskAccessCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    let hant = Locale(identifier: "zh-Hant")
    let ja = Locale(identifier: "ja")
    let keys = [
      "settings.fda", "fda.body", "fda.open", "fda.statusGranted", "fda.statusDenied",
      "fda.helperPath", "helper.fdaHint", "diagnose.fdaGranted", "diagnose.fdaDenied",
      "diagnose.fdaUnknown",
    ]
    for key in keys {
      XCTAssertNotEqual(L10n.t(key, locale: en), key, "missing en \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: zh), key, "missing zh-Hans \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: hant), key, "missing zh-Hant \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: ja), key, "missing ja \(key)")
      XCTAssertNotEqual(L10n.t(key, locale: en), L10n.t(key, locale: zh))
    }
    let body = L10n.t("fda.body", locale: en)
    XCTAssertTrue(body.contains("Full Disk Access"))
    XCTAssertTrue(body.contains("does not inherit"))
    XCTAssertTrue(body.contains("occupier"))
    XCTAssertTrue(body.contains("LaunchDaemon"))
    XCTAssertFalse(body.localizedCaseInsensitiveContains("inherits the app"))
    XCTAssertTrue(L10n.t("helper.fdaHint", locale: en).contains("does not inherit"))
    XCTAssertTrue(L10n.t("fda.open", locale: en).contains("Full Disk Access"))
    XCTAssertTrue(L10n.format("fda.helperPath", FullDiskAccess.helperInstallPath, locale: en)
      .contains(FullDiskAccess.helperInstallPath))
    XCTAssertTrue(L10n.t("diagnose.fdaUnknown", locale: zh).contains("不会继承"))
    XCTAssertTrue(L10n.t("fda.body", locale: ja).contains("継承しません"))
  }

  func testDiskStatusAndAboutCatalogs() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
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
      "forceUnmount.action", "forceUnmount.occupiers", "repairEnv.title", "repairEnv.body", "repairEnv.action",
      "repairEnv.working", "repairEnv.summary", "repairEnv.summaryBusy", "repairEnv.summaryNone",
      "repairEnv.helperRestarted", "repairEnv.failed", "menu.repairEnv",
      "diskStatus.mountMode", "diskStatus.mountRW", "diskStatus.mountRO", "diskStatus.used",
      "diskStatus.encryption", "diskStatus.encryptionHint", "diskStatus.encryptionNone",
      "diskStatus.journal", "diskStatus.journalUnknown", "diskStatus.journalDirty",
      "diskStatus.journalHibernated", "diskStatus.journalCorrupt", "diskStatus.journalClean",
      "settings.autoMount", "settings.autoMountNote", "settings.autoMountNeedHelper",
      "settings.cleanMacJunk", "settings.cleanMacJunkNote", "cleanJunk.working", "cleanJunk.done",
      "cleanJunk.failedTitle", "cleanJunk.failedBody", "cleanJunk.continueWithout",
      "helper.privilegeHint", "helper.hintAdHoc", "helper.hintNotarized", "privileged.authUnavailable",
      "helper.fdaHint", "fda.body", "fda.open", "fda.statusGranted", "fda.statusDenied",
      "fda.helperPath", "settings.fda", "diagnose.fdaGranted", "diagnose.fdaDenied", "diagnose.fdaUnknown",
      "dirty.title", "dirty.body", "premount.dirtyTitle", "premount.hiberTitle",
      "status.roDirty", "error.diskBusy", "error.diskBusyNamed", "error.occupiersMore",
      "error.diskBusyNeedFDA", "window.usageAfterMount",
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
