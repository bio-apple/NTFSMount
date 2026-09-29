import Foundation
import NTFSMountCore
import XCTest

final class OnboardingCopyTests: XCTestCase {
  func testAgreeIsPrimaryAndBodyMentionsHelper() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(OnboardingCopy.quitTitle(locale: zh), "退出")
    XCTAssertEqual(OnboardingCopy.agreeTitle(locale: zh), "同意并继续")
    let body = OnboardingCopy.body(notarized: false, locale: zh)
    XCTAssertTrue(body.contains("管理员密码"))
    XCTAssertTrue(body.contains("go-nfsv4"))
    XCTAssertTrue(body.contains("回车即同意"))
    XCTAssertTrue(body.contains("安装"))
    XCTAssertEqual(OnboardingCopy.copyVersion, 6)
    XCTAssertFalse(UpdateCopy.feedURL.lowercased().contains("latest"))
    XCTAssertTrue(UpdateCopy.feedURL.contains("v1.0/appcast.xml"))
    XCTAssertFalse(OnboardingCopy.body(notarized: false, locale: zh).contains("检查更新"))
    XCTAssertFalse(OnboardingCopy.body(notarized: false, locale: zh).contains("v1.2.0"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("GitHub Releases"))
    XCTAssertTrue(OnboardingCopy.body(notarized: false, locale: zh).contains("当前构建未公证"))
    XCTAssertTrue(OnboardingCopy.gatekeeperBody(locale: zh).contains("仍要打开"))
  }
}
