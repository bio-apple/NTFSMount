import Foundation
import NTFSMountCore
import XCTest

final class DiagnoseExportTests: XCTestCase {
  func testArchiveFileListIsDocumented() {
    XCTAssertEqual(DiagnoseExport.archiveFiles, [
      "README.txt",
      "diagnose.txt",
      "diagnose.json",
      "versions.txt",
      "disk-status.txt",
      "unified-log.txt",
    ])
    let payload = DiagnoseExport.Payload(
      diagnoseText: "human",
      diagnoseJSON: "{}",
      versionsText: "FUSE-T 1.2.7",
      diskStatusText: "disk4s1",
      unifiedLogText: "note",
      readmeText: DiagnoseExport.readmeText(locale: Locale(identifier: "en"))
    )
    XCTAssertEqual(DiagnoseExport.files(from: payload).map(\.name), DiagnoseExport.archiveFiles)
    let readme = DiagnoseExport.readmeText(locale: Locale(identifier: "en"))
    for name in DiagnoseExport.archiveFiles {
      XCTAssertTrue(readme.contains(name), "README should list \(name)")
    }
  }

  func testDefaultZipNameUsesLocalCalendarDate() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 1_790_553_600)
    XCTAssertEqual(
      DiagnoseExport.defaultFileName(date: date, calendar: cal),
      "NTFSMount-diagnose-20260928.zip"
    )
  }

  func testLogShowPredicateMatchesIssueTemplate() {
    XCTAssertEqual(DiagnoseExport.logShowArguments[0], "show")
    XCTAssertEqual(DiagnoseExport.logShowArguments[1], "--last")
    XCTAssertEqual(DiagnoseExport.logShowArguments[2], "1h")
    XCTAssertEqual(DiagnoseExport.logShowArguments[3], "--predicate")
    XCTAssertEqual(
      DiagnoseExport.logShowPredicate,
      #"subsystem CONTAINS "bioapple" OR process CONTAINS "NTFSMount" OR process CONTAINS "ntfsmount""#
    )
  }

  func testSnapshotJSONRoundTripKeepsRuntime() {
    var snap = DiagnoseSnapshot()
    snap.appleSilicon = true
    snap.arch = "arm64"
    snap.macosProduct = "macOS"
    snap.macosVersion = "15.6"
    snap.bundledNtfs3g = true
    snap.bundledNtfsfix = true
    snap.bundledGoNfsv4 = true
    snap.goNfsv4Path = "/Applications/NTFSMount.app/Contents/MacOS/go-nfsv4"
    snap.ntfs3gVersion = "2026.7.7"
    snap.ntfs3gAllowed = true
    snap.pinnedFuseT = "1.2.7"
    snap.systemFuseTVersion = "1.2.8"
    snap.helperSocketExists = true
    snap.helperPing = "HELPER_VERSION=9"
    let json = DiagnoseExport.snapshotJSON(snap)
    XCTAssertTrue(json.contains("\"source\" : \"in-process\"") || json.contains("\"source\":\"in-process\""))
    let parsed = EnvironmentDiagnose.parseJSON(json.data(using: .utf8)!)
    XCTAssertEqual(parsed?.appleSilicon, true)
    XCTAssertEqual(parsed?.bundledNtfs3g, true)
    XCTAssertEqual(parsed?.ntfs3gVersion, "2026.7.7")
    XCTAssertEqual(parsed?.systemFuseTVersion, "1.2.8")
    XCTAssertEqual(parsed?.pinnedFuseT, "1.2.7")
  }

  func testDiskStatusTextKeepsIdentifierAndPrivacy() {
    let en = Locale(identifier: "en")
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 1_000_000_000,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 1,
      freeBytes: 1
    )
    let text = DiagnoseExport.diskStatusText(
      volumes: [vol],
      diskutilList: "/dev/disk4 (external, physical)",
      locale: en
    )
    XCTAssertTrue(text.contains("disk4s1"))
    XCTAssertTrue(text.contains("T7"))
    XCTAssertTrue(text.contains("identifier: disk4s1"))
    XCTAssertTrue(text.contains("/dev/disk4"))
    XCTAssertTrue(text.contains(L10n.t("diagnose.exportPrivacy", locale: en)))
    let empty = DiagnoseExport.diskStatusText(volumes: [], diskutilList: nil, locale: en)
    XCTAssertTrue(empty.contains(L10n.t("diagnose.exportNoVolumes", locale: en)))
    XCTAssertTrue(empty.contains(L10n.t("diagnose.exportDiskutilFailed", locale: en)))
  }

  func testLogNotesDoNotRequireFullDiskAccess() {
    let en = Locale(identifier: "en")
    let note = DiagnoseExport.logShowUnavailableNote(status: -1, detail: "operation not permitted", locale: en)
    XCTAssertTrue(note.contains(L10n.t("diagnose.exportLogUnavailable", locale: en)))
    XCTAssertTrue(note.contains("status: -1"))
    XCTAssertFalse(L10n.t("diagnose.exportLogUnavailable", locale: en).localizedCaseInsensitiveContains("must"))
    XCTAssertTrue(DiagnoseExport.logShowEmptyNote(locale: en).contains(
      L10n.t("diagnose.exportLogEmpty", locale: en)
    ))
  }

  func testVersionsTextIncludesLiveAndBundled() {
    var snap = DiagnoseSnapshot()
    snap.pinnedFuseT = "1.2.7"
    snap.systemFuseTVersion = "1.2.7"
    snap.bundledGoNfsv4 = true
    snap.ntfs3gVersion = "2026.7.7"
    let text = DiagnoseExport.versionsText(snap: snap, bundledFile: "FUSE-T          1.2.7\nntfs-3g         2026.7.7")
    XCTAssertTrue(text.contains("pinned_fuse_t: 1.2.7"))
    XCTAssertTrue(text.contains("ntfs_3g_version: 2026.7.7"))
    XCTAssertTrue(text.contains("FUSE-T          1.2.7"))
  }
}
