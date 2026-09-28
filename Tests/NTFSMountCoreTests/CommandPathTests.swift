import NTFSMountCore
import XCTest

final class CommandPathTests: XCTestCase {
  func testFindsLaunchctlWithoutAssumingBinOrUsrBin() {
    guard let path = CommandPath.find("launchctl") else {
      return XCTFail("launchctl must exist in system dirs")
    }
    XCTAssertTrue(path.hasSuffix("/launchctl"))
    XCTAssertTrue(CommandPath.systemDirs.contains { path.hasPrefix($0 + "/") })
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
  }

  func testFindsDiskutilMountBashAndRejectsMissing() {
    XCTAssertNotNil(CommandPath.find("diskutil"))
    XCTAssertNotNil(CommandPath.find("mount"))
    XCTAssertNotNil(CommandPath.find("bash"))
    XCTAssertNil(CommandPath.find("ntfsmount-definitely-missing-cmd"))
  }

  func testAbsolutePathMustExistAndBeExecutable() {
    XCTAssertNil(CommandPath.find("/no/such/launchctl"))
    if let sh = CommandPath.find("sh") {
      XCTAssertEqual(CommandPath.find(sh), sh)
    }
  }
}
