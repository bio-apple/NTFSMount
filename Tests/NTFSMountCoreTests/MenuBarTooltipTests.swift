import Foundation
import NTFSMountCore
import XCTest

final class MenuBarTooltipTests: XCTestCase {
  func testCardMatchesMenuBarMockup() {
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 931_000_000_000,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 512_000_000_000,
      freeBytes: 419_000_000_000
    )
    let lines = MenuBarTooltip.card(vol, locale: Locale(identifier: "en"))
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    XCTAssertEqual(lines.count, 4)
    XCTAssertEqual(lines[0], "Samsung T7")
    XCTAssertEqual(lines[1], "NTFS • RW")
    XCTAssertEqual(lines[2], "disk4s1")
    XCTAssertTrue(lines[3].contains(" / "))
  }

  func testCardFallsBackToVolumeNameWhenMediaNameMissing() {
    let vol = NTFSVolume(
      id: "disk5s1",
      name: "WINDATA",
      size: 8_000_000_000,
      mountPoint: "",
      isWritableFuse: false,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "",
      usedBytes: 0,
      freeBytes: 0
    )
    let card = MenuBarTooltip.card(vol, locale: Locale(identifier: "en"))
    XCTAssertTrue(card.hasPrefix("WINDATA\n"))
    XCTAssertTrue(card.contains("NTFS • —"))
    XCTAssertTrue(card.contains("disk5s1"))
  }

  func testExtraJoinsCardsAndEmptyUsesNoNTFSCopy() {
    let empty = MenuBarTooltip.extra([], locale: Locale(identifier: "en"))
    XCTAssertEqual(empty, L10n.t("menu.noNTFS", locale: Locale(identifier: "en")))
    let a = NTFSVolume(
      id: "disk4s1",
      name: "A",
      size: 1,
      mountPoint: "",
      isWritableFuse: false,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Drive A",
      usedBytes: 0,
      freeBytes: 0
    )
    let volB = NTFSVolume(
      id: "disk5s1",
      name: "B",
      size: 1,
      mountPoint: "/Volumes/B",
      isWritableFuse: false,
      isReadOnlyMounted: true,
      isInternal: false,
      mediaName: "Drive B",
      usedBytes: 0,
      freeBytes: 0
    )
    let extra = MenuBarTooltip.extra([a, volB], locale: Locale(identifier: "en"))
    XCTAssertTrue(extra.contains("Drive A"))
    XCTAssertTrue(extra.contains("Drive B"))
    XCTAssertTrue(extra.contains("NTFS • RO"))
    XCTAssertTrue(extra.contains("\n\n"))
  }

  func testZhHansUsesWritableMark() {
    let vol = NTFSVolume(
      id: "disk4s1",
      name: "T7",
      size: 1,
      mountPoint: "/Volumes/T7",
      isWritableFuse: true,
      isReadOnlyMounted: false,
      isInternal: false,
      mediaName: "Samsung T7",
      usedBytes: 1,
      freeBytes: 1
    )
    let card = MenuBarTooltip.card(vol, locale: Locale(identifier: "zh-Hans"))
    XCTAssertTrue(card.contains("NTFS • 可写"))
  }
}
