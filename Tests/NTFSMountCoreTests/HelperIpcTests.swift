import Foundation
import NTFSMountCore
import XCTest

final class HelperIpcTests: XCTestCase {
  func testV2RoundTripKeepsNewlinesInVolumeLabel() {
    let args = ["format", "disk4s1", "Win\nData"]
    guard let data = HelperIpc.encodeV2(args) else {
      return XCTFail("encode")
    }
    XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("v1 ") == true)
    XCTAssertEqual(HelperIpc.decodeV2(data), args)
  }

  func testV2RoundTripKeepsForceFlagAndSpacedCJKLabels() {
    let unmount = ["unmount", "disk5s1", "force"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(unmount)!), unmount)
    let passport = ["format", "disk4", "My Passport"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(passport)!), passport)
    let cjk = ["format", "disk4", "移动硬盘"]
    XCTAssertEqual(HelperIpc.decodeV2(HelperIpc.encodeV2(cjk)!), cjk)
  }

  func testV2RejectsTooManyArgs() {
    let args = Array(repeating: "x", count: HelperIpc.maxArgs + 1)
    XCTAssertNil(HelperIpc.encodeV2(args))
  }

  func testV1CompatStillStripsNewlines() {
    let data = HelperIpc.encodeV1Compat(["format", "disk4s1", "A\nB"])
    let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
    XCTAssertTrue(text.hasPrefix("v1 3\n"))
    XCTAssertTrue(text.contains("A B\n"))
    XCTAssertFalse(text.contains("A\nB"))
  }

  func testHeartbeatNULsAreStrippedBeforeOK() {
    var data = Data([0, 0])
    data.append(contentsOf: Array("OK\nrw\n".utf8))
    data.append(0)
    let text = String(data: HelperIpc.stripHeartbeats(data), encoding: .utf8)
    XCTAssertEqual(text, "OK\nrw\n")
  }

  func testFormatUsesTenMinuteRecvTimeout() {
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "format"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "fix"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "ntfsfix"), 600)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "mount"), 180)
    XCTAssertEqual(HelperIpc.recvTimeoutSec(command: "probe"), 180)
  }
}
