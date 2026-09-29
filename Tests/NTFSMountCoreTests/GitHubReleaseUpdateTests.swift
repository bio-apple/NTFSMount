import Foundation
import NTFSMountCore
import XCTest

final class GitHubReleaseUpdateTests: XCTestCase {
  func testNormalizeStripsVPrefix() {
    XCTAssertEqual(GitHubReleaseUpdate.normalizeVersion("v1.2.0"), "1.2.0")
    XCTAssertEqual(GitHubReleaseUpdate.normalizeVersion("V1.0.0"), "1.0.0")
    XCTAssertEqual(GitHubReleaseUpdate.normalizeVersion("  1.0.0  "), "1.0.0")
  }

  func testCompareNumericComponents() {
    XCTAssertEqual(GitHubReleaseUpdate.compare("1.0.0", "1.0.0"), .orderedSame)
    XCTAssertEqual(GitHubReleaseUpdate.compare("v1.0.0", "1.0.1"), .orderedAscending)
    XCTAssertEqual(GitHubReleaseUpdate.compare("1.2.0", "1.0.9"), .orderedDescending)
    XCTAssertEqual(GitHubReleaseUpdate.compare("1.0", "1.0.0"), .orderedSame)
    XCTAssertEqual(GitHubReleaseUpdate.compare("1.0.0", "1.0.0.1"), .orderedAscending)
  }

  func testShouldPromptRespectsSkipAndNewer() {
    XCTAssertFalse(GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "1.0.0", skipped: nil))
    XCTAssertFalse(GitHubReleaseUpdate.shouldPrompt(current: "1.2.0", remote: "1.0.0", skipped: nil))
    XCTAssertTrue(GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "1.0.1", skipped: nil))
    XCTAssertTrue(GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "v1.1.0", skipped: nil))

    XCTAssertFalse(
      GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "1.1.0", skipped: "1.1.0")
    )
    XCTAssertFalse(
      GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "v1.1.0", skipped: "1.1.0")
    )
    XCTAssertTrue(
      GitHubReleaseUpdate.shouldPrompt(current: "1.0.0", remote: "1.2.0", skipped: "1.1.0"),
      "a newer remote than the skipped version may prompt again"
    )
  }

  func testTagNameFromLatestReleaseJSON() throws {
    let json = """
    {"tag_name":"v1.0","name":"1.0","draft":false,"prerelease":false}
    """.data(using: .utf8)!
    XCTAssertEqual(GitHubReleaseUpdate.tagName(fromLatestReleaseJSON: json), "1.0")

    let bad = Data("{}".utf8)
    XCTAssertNil(GitHubReleaseUpdate.tagName(fromLatestReleaseJSON: bad))
    XCTAssertNil(GitHubReleaseUpdate.tagName(fromLatestReleaseJSON: Data()))
  }

  func testEmptyVersionsStayQuiet() {
    XCTAssertFalse(GitHubReleaseUpdate.isRemoteNewer(current: "", remote: "1.0.0"))
    XCTAssertFalse(GitHubReleaseUpdate.isRemoteNewer(current: "1.0.0", remote: ""))
    XCTAssertFalse(GitHubReleaseUpdate.shouldPrompt(current: "", remote: "1.0.0", skipped: nil))
  }
}
