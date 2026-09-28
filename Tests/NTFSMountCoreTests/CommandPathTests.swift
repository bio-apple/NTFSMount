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

  func testFindsLsofAndFuserInSystemDirs() {
    guard let lsof = CommandPath.find("lsof") else {
      return XCTFail("lsof must exist in system dirs")
    }
    XCTAssertTrue(lsof.hasSuffix("/lsof"))
    XCTAssertTrue(CommandPath.systemDirs.contains { lsof.hasPrefix($0 + "/") })
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: lsof))
    if let fuser = CommandPath.find("fuser") {
      XCTAssertTrue(fuser.hasSuffix("/fuser"))
      XCTAssertTrue(CommandPath.systemDirs.contains { fuser.hasPrefix($0 + "/") })
    }
  }

  func testAbsolutePathMustExistAndBeExecutable() {
    XCTAssertNil(CommandPath.find("/no/such/launchctl"))
    if let sh = CommandPath.find("sh") {
      XCTAssertEqual(CommandPath.find(sh), sh)
    }
  }
}
