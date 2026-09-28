import Foundation
import NTFSMountCore
import XCTest

final class FullDiskAccessTests: XCTestCase {
  func testProbeUsesReadabilityNotTCCScrape() {
    XCTAssertEqual(
      FullDiskAccess.probe(pathExists: { _ in false }, pathIsReadable: { _ in true }),
      .unknown
    )
    XCTAssertEqual(
      FullDiskAccess.probe(pathExists: { _ in true }, pathIsReadable: { _ in true }),
      .granted
    )
    XCTAssertEqual(
      FullDiskAccess.probe(pathExists: { _ in true }, pathIsReadable: { _ in false }),
      .denied
    )
    XCTAssertEqual(FullDiskAccess.gatedPath, "/Library/Application Support/com.apple.TCC/TCC.db")
    XCTAssertEqual(
      FullDiskAccess.helperInstallPath,
      "/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
    )
  }

  func testPromptOnlyWhenAccessMissingAndNotYetAsked() {
    XCTAssertTrue(FullDiskAccess.shouldPrompt(status: .denied, alreadyPrompted: false))
    XCTAssertTrue(FullDiskAccess.shouldPrompt(status: .unknown, alreadyPrompted: false))
    XCTAssertFalse(FullDiskAccess.shouldPrompt(status: .granted, alreadyPrompted: false))
    XCTAssertFalse(FullDiskAccess.shouldPrompt(status: .denied, alreadyPrompted: true))
  }

  func testLiveProbeDoesNotRequireGranted() {
    let status = FullDiskAccess.probe()
    XCTAssertTrue([FullDiskAccess.Status.granted, .denied, .unknown].contains(status))
  }

  func testSettingsURLsPreferSequoiaThenLegacy() {
    let sequoia = FullDiskAccess.settingsURLs(macosMajor: 15).map(\.absoluteString)
    XCTAssertTrue(sequoia.contains {
      $0 == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    })
    XCTAssertEqual(sequoia.last, "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    XCTAssertTrue(sequoia.allSatisfy { $0.contains("Privacy_AllFiles") })

    let ventura = FullDiskAccess.settingsURLs(macosMajor: 13).map(\.absoluteString)
    XCTAssertEqual(ventura, [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
    ])
  }

  func testDiagnoseLineDoesNotFailWithoutFDA() {
    var unknown = DiagnoseSnapshot()
    unknown.fullDiskAccess = .unknown
    let unknownLine = EnvironmentDiagnose.lines(from: unknown).first {
      $0.id == FullDiskAccess.diagnoseLineId
    }
    XCTAssertEqual(unknownLine?.status, .info)
    XCTAssertNotEqual(unknownLine?.status, .fail)

    var denied = DiagnoseSnapshot()
    denied.fullDiskAccess = .denied
    let deniedLine = EnvironmentDiagnose.lines(from: denied).first {
      $0.id == FullDiskAccess.diagnoseLineId
    }
    XCTAssertEqual(deniedLine?.status, .conflict)
    XCTAssertNotEqual(deniedLine?.status, .fail)

    var granted = DiagnoseSnapshot()
    granted.fullDiskAccess = .granted
    let grantedLine = EnvironmentDiagnose.lines(from: granted, locale: Locale(identifier: "en"))
      .first { $0.id == FullDiskAccess.diagnoseLineId }
    XCTAssertEqual(grantedLine?.status, .pass)
    XCTAssertTrue(grantedLine?.title.contains("does not inherit") == true)
  }

  func testParsePrefersAppStatusOverProcess() {
    XCTAssertEqual(FullDiskAccess.parseStatus("granted"), .granted)
    XCTAssertEqual(FullDiskAccess.parseStatus("DENIED"), .denied)
    XCTAssertEqual(FullDiskAccess.parseStatus(nil), .unknown)
    let json = """
    {"full_disk_access":{"app":"granted","process":"denied"}}
    """.data(using: .utf8)!
    XCTAssertEqual(EnvironmentDiagnose.parseJSON(json)?.fullDiskAccess, .granted)
  }
}
