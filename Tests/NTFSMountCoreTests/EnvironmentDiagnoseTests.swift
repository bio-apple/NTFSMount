import Foundation
import NTFSMountCore
import XCTest

final class EnvironmentDiagnoseTests: XCTestCase {
  private let zh = Locale(identifier: "zh-Hans")

  func testHealthySnapshotMarksPassAndInfoNotMacFuseInstall() {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = true
    snap.arch = "arm64"
    snap.macosProduct = "macOS"
    snap.macosVersion = "15.6.1"
    snap.macosMajor = 15
    snap.bundledNtfs3g = true
    snap.bundledNtfsfix = true
    snap.bundledGoNfsv4 = true
    snap.goNfsv4Path = "/Applications/NTFSMount.app/Contents/MacOS/go-nfsv4"
    snap.ntfs3gVersion = "2026.7.7"
    snap.ntfs3gAllowed = true
    snap.pinnedFuseT = "1.2.7"
    snap.helperSocketExists = true
    snap.helperPing = "HELPER_VERSION=5"
    snap.brewMacFuse = "absent"
    snap.kextMacFuse = "absent"
    snap.sysextMacFuse = "absent"
    snap.quarantine = false
    snap.spctl = "accepted"
    let lines = EnvironmentDiagnose.lines(from: snap, locale: Locale(identifier: "zh-Hans"))
    XCTAssertEqual(lines.map(\.id), [
      "platform", "runtime", "ntfs_3g_version", "fuse_t", "helper", "gatekeeper",
    ])
    XCTAssertEqual(line(lines, "platform").status, .pass)
    XCTAssertTrue(line(lines, "platform").title.contains("Apple Silicon"))
    XCTAssertEqual(line(lines, "runtime").status, .pass)
    XCTAssertEqual(line(lines, "fuse_t").status, .pass)
    XCTAssertTrue(line(lines, "fuse_t").title.contains("1.2.7"))
    XCTAssertEqual(line(lines, "helper").status, .pass)
    XCTAssertNil(lines.first { $0.id == "macfuse_conflict" })
    XCTAssertEqual(line(lines, "gatekeeper").status, .pass)
    let report = EnvironmentDiagnose.reportText(from: lines, locale: Locale(identifier: "zh-Hans"))
    XCTAssertTrue(report.contains("✅"))
    XCTAssertTrue(report.contains("只读"))
    XCTAssertFalse(report.contains("macFUSE"))
    XCTAssertFalse(report.contains("请安装 macFUSE"))
    XCTAssertFalse(report.contains("brew install macfuse"))
  }

  func testIntelAndOldMacOSFailPlatform() {
    var intel = DiagnoseSnapshot()
    intel.appleSilicon = false
    intel.arch = "x86_64"
    intel.macosMajor = 15
    intel.macosVersion = "15.0"
    XCTAssertEqual(line(EnvironmentDiagnose.lines(from: intel, locale: zh), "platform").status, .fail)
    XCTAssertTrue(line(EnvironmentDiagnose.lines(from: intel, locale: zh), "platform").title.contains("Intel"))

    var old = DiagnoseSnapshot()
    old.appleSilicon = true
    old.arch = "arm64"
    old.macosMajor = 12
    old.macosProduct = "macOS"
    old.macosVersion = "12.7"
    let platform = line(EnvironmentDiagnose.lines(from: old, locale: zh), "platform")
    XCTAssertEqual(platform.status, .fail)
    XCTAssertTrue(platform.title.contains("13"))
  }

  func testMissingRuntimeAndHelperNeverAskMacFuse() {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = true
    snap.macosMajor = 14
    snap.helperSocketExists = false
    let lines = EnvironmentDiagnose.lines(from: snap, locale: zh)
    XCTAssertEqual(line(lines, "runtime").status, .fail)
    XCTAssertTrue(line(lines, "runtime").title.contains("ntfs-3g"))
    XCTAssertFalse(line(lines, "runtime").title.contains("macFUSE"))
    XCTAssertEqual(line(lines, "fuse_t").status, .fail)
    XCTAssertTrue(line(lines, "fuse_t").title.contains("go-nfsv4"))
    XCTAssertFalse(line(lines, "fuse_t").title.contains("macFUSE"))
    XCTAssertEqual(line(lines, "helper").status, .fail)
    XCTAssertTrue(line(lines, "helper").title.contains("不会去安装"))
    XCTAssertTrue(EnvironmentDiagnose.helperNeedsInstall(snap))
    XCTAssertTrue(EnvironmentDiagnose.bundledComponentsBroken(snap))
  }

  func testHelperInstallableIsSocketNotMacFuse() {
    var snap = DiagnoseSnapshot()
    snap.helperSocketExists = false
    snap.brewMacFuse = "absent"
    snap.kextMacFuse = "absent"
    XCTAssertTrue(EnvironmentDiagnose.helperNeedsInstall(snap))
    XCTAssertTrue(EnvironmentDiagnose.bundledComponentsBroken(snap))

    snap.helperSocketExists = true
    snap.helperPing = "HELPER_VERSION=9"
    snap.bundledNtfs3g = true
    snap.bundledNtfsfix = true
    snap.bundledGoNfsv4 = true
    XCTAssertFalse(EnvironmentDiagnose.helperNeedsInstall(snap))
    XCTAssertFalse(EnvironmentDiagnose.bundledComponentsBroken(snap))

    snap.helperPing = "connect_failed: timeout"
    XCTAssertTrue(EnvironmentDiagnose.helperNeedsInstall(snap))
    snap.helperPing = "HELPER_VERSION=9"
    snap.brewMacFuse = "present"
    XCTAssertFalse(EnvironmentDiagnose.helperNeedsInstall(snap))
  }

  func testHelperOfferIsUpdateRequiresLiveSocket() {
    XCTAssertFalse(EnvironmentDiagnose.helperOfferIsUpdate(socketExists: false, helperNeedsUpdate: true))
    XCTAssertFalse(EnvironmentDiagnose.helperOfferIsUpdate(socketExists: false, helperNeedsUpdate: false))
    XCTAssertFalse(EnvironmentDiagnose.helperOfferIsUpdate(socketExists: true, helperNeedsUpdate: false))
    XCTAssertTrue(EnvironmentDiagnose.helperOfferIsUpdate(socketExists: true, helperNeedsUpdate: true))
  }

  func testMacFusePresentIsConflictNotRequirement() {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = true
    snap.macosMajor = 14
    snap.bundledNtfs3g = true
    snap.bundledNtfsfix = true
    snap.bundledGoNfsv4 = true
    snap.brewMacFuse = "present"
    snap.kextMacFuse = "present"
    snap.sysextMacFuse = "absent"
    let conflict = line(EnvironmentDiagnose.lines(from: snap, locale: zh), "macfuse_conflict")
    XCTAssertEqual(conflict.status, .conflict)
    XCTAssertTrue(conflict.title.contains("可能干扰"))
    XCTAssertFalse(conflict.title.contains("请安装"))
  }

  func testBrewMissingIsInfoAndRejectedPingIsPass() {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = true
    snap.macosMajor = 14
    snap.bundledNtfs3g = true
    snap.bundledNtfsfix = true
    snap.bundledGoNfsv4 = true
    snap.brewMacFuse = "brew_missing"
    snap.kextMacFuse = "absent"
    snap.helperSocketExists = true
    snap.helperPing = "alive_caller_rejected"
    snap.quarantine = true
    let lines = EnvironmentDiagnose.lines(from: snap, locale: zh)
    XCTAssertNil(lines.first { $0.id == "macfuse_conflict" })
    XCTAssertEqual(line(lines, "helper").status, .pass)
    XCTAssertEqual(line(lines, "gatekeeper").status, .fail)
    XCTAssertTrue(line(lines, "gatekeeper").title.contains("隔离"))
  }

  func testParseJSONSchema2AndLegacyFuseT() {
    let json = """
    {
      "schema_version": 2,
      "arch": "arm64",
      "apple_silicon": true,
      "macos_product_name": "macOS",
      "macos_version": "15.6",
      "fuse_t": {
        "bundled_present": true,
        "bundled_go_nfsv4": "/tmp/go-nfsv4",
        "pinned_version": "1.2.7",
        "system_version": "1.2.7"
      },
      "runtime": {
        "ntfs_3g_present": true,
        "ntfsfix_present": true,
        "go_nfsv4_present": true,
        "pinned_fuse_t": "1.2.7"
      },
      "helper": { "socket_exists": false, "ping": "absent" },
      "conflicts": {
        "brew_macfuse": "brew_missing",
        "kext_macfuse": "absent",
        "systemextensions_macfuse": "absent"
      },
      "gatekeeper": { "quarantine": false, "spctl": "notarized" }
    }
    """.data(using: .utf8)!
    let snap = EnvironmentDiagnose.parseJSON(json)
    XCTAssertNotNil(snap)
    XCTAssertEqual(snap?.appleSilicon, true)
    XCTAssertEqual(snap?.macosMajor, 15)
    XCTAssertEqual(snap?.bundledNtfs3g, true)
    XCTAssertEqual(snap?.bundledGoNfsv4, true)
    XCTAssertEqual(snap?.pinnedFuseT, "1.2.7")
    XCTAssertEqual(snap?.brewMacFuse, "brew_missing")
    XCTAssertEqual(snap?.spctl, "notarized")
    XCTAssertEqual(EnvironmentDiagnose.majorVersion("13.0.1"), 13)
  }

  private func line(_ lines: [DiagnoseLine], _ id: String) -> DiagnoseLine {
    lines.first { $0.id == id }!
  }
}
