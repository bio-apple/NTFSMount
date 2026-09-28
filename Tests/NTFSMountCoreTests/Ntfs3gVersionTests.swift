import Foundation
import NTFSMountCore
import XCTest

final class Ntfs3gVersionTests: XCTestCase {
  func testAllowPinnedAnd2026_8() {
    XCTAssertTrue(Ntfs3gVersion.parse("ntfs-3g 2026.7.7 external FUSE 29").isAllowed)
    XCTAssertEqual(Ntfs3gVersion.parse("ntfs-3g 2026.7.7 external FUSE 29").displayVersion, "2026.7.7")
    XCTAssertEqual(Ntfs3gVersion.parse("ntfs-3g 2026.7.7 external FUSE 29").status, .allowed)

    XCTAssertTrue(Ntfs3gVersion.parse("ntfs-3g 2026.8.1 integrated FUSE 29").isAllowed)
    XCTAssertEqual(Ntfs3gVersion.parse("ntfs-3g 2026.8.1 integrated FUSE 29").displayVersion, "2026.8.1")

    XCTAssertTrue(Ntfs3gVersion.parse("ntfs-3g 2026.8.0 external FUSE 29").isAllowed)
    XCTAssertTrue(Ntfs3gVersion.parse("ntfs-3g 2026.8.99 external FUSE 29").isAllowed)
    XCTAssertTrue(Ntfs3gVersion.parse("ntfs-3g v2026.7.7").isAllowed)
    XCTAssertEqual(Ntfs3gVersion.pinned, "2026.7.7")
  }

  func testWarnOlderNewerAndGarbage() {
    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2024.2.1 external FUSE 28").isAllowed)
    XCTAssertEqual(Ntfs3gVersion.parse("ntfs-3g 2024.2.1 external FUSE 28").status, .untested)

    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2026.9.0 external FUSE 29").isAllowed)
    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2026.9.1").isAllowed)
    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2026.7.6").isAllowed)
    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2026.7.8").isAllowed)
    XCTAssertFalse(Ntfs3gVersion.parse("ntfs-3g 2026.8.100").isAllowed)

    let garbage = Ntfs3gVersion.parse("not a version at all")
    XCTAssertFalse(garbage.isAllowed)
    XCTAssertEqual(garbage.status, .untested)
    XCTAssertEqual(garbage.displayVersion, "unknown")

    XCTAssertEqual(Ntfs3gVersion.parse("").status, .missing)
    XCTAssertFalse(Ntfs3gVersion.parse("").isAllowed)
  }

  func testDiagnoseLineWarnsWithoutBlocking() {
    let zh = Locale(identifier: "zh-Hans")
    var snap = DiagnoseSnapshot()
    snap.bundledNtfs3g = true
    snap.ntfs3gVersion = "2026.7.7"
    snap.ntfs3gAllowed = true
    let ok = EnvironmentDiagnose.lines(from: snap, locale: zh).first { $0.id == Ntfs3gVersion.diagnoseLineId }
    XCTAssertEqual(ok?.status, .pass)
    XCTAssertTrue(ok?.title.contains("2026.7.7") == true)

    snap.ntfs3gVersion = "2024.2.1"
    snap.ntfs3gAllowed = false
    let warn = EnvironmentDiagnose.lines(from: snap, locale: zh).first { $0.id == Ntfs3gVersion.diagnoseLineId }
    XCTAssertEqual(warn?.status, .conflict)
    XCTAssertTrue(warn?.title.contains("未经测试") == true)
    XCTAssertTrue(warn?.title.contains("仍可继续挂载") == true)

    let missing = DiagnoseSnapshot()
    let miss = EnvironmentDiagnose.lines(from: missing, locale: zh).first { $0.id == Ntfs3gVersion.diagnoseLineId }
    XCTAssertEqual(miss?.status, .fail)
    XCTAssertEqual(miss?.title, Ntfs3gVersion.diagnoseMissing(locale: zh))
    XCTAssertTrue(miss?.title.contains("GitHub Latest") == true)
    XCTAssertEqual(
      Ntfs3gVersion.settingsLine(Ntfs3gVersion.parse(""), locale: zh),
      L10n.t("runtime.ntfs3gMissing", locale: zh)
    )
  }

  func testParseJSONRuntimeVersion() throws {
    let json = """
    {
      "apple_silicon": true,
      "arch": "arm64",
      "macos_product_name": "macOS",
      "macos_version": "15.0",
      "runtime": {
        "ntfs_3g_present": true,
        "ntfs_3g_path": "/tmp/runtime/ntfs-3g",
        "ntfs_3g_version": "2026.8.1",
        "ntfs_3g_allowed": true,
        "ntfs_3g_raw": "ntfs-3g 2026.8.1 external FUSE 29",
        "ntfsfix_present": true,
        "go_nfsv4_present": true
      }
    }
    """.data(using: .utf8)!
    let snap = try XCTUnwrap(EnvironmentDiagnose.parseJSON(json))
    XCTAssertEqual(snap.ntfs3gVersion, "2026.8.1")
    XCTAssertEqual(snap.ntfs3gAllowed, true)
    XCTAssertEqual(snap.ntfs3gPath, "/tmp/runtime/ntfs-3g")
    let line = EnvironmentDiagnose.lines(from: snap).first { $0.id == Ntfs3gVersion.diagnoseLineId }
    XCTAssertEqual(line?.status, .pass)
  }
}
