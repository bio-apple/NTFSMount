import Foundation
import NTFSMountCore
import XCTest

final class MacJunkCleanupTests: XCTestCase {
  func testMatcherKeepsDocumentsAndProtectedWindowsFiles() {
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".DS_Store", isDirectory: false, isSymbolicLink: false))
    XCTAssertFalse(MacJunkCleanup.isJunkItem(name: ".DS_Store", isDirectory: true, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: "._photo.jpg", isDirectory: false, isSymbolicLink: false))
    XCTAssertFalse(MacJunkCleanup.isJunkItem(name: "._photo.jpg", isDirectory: true, isSymbolicLink: false))
    XCTAssertFalse(MacJunkCleanup.isJunkItem(name: "photo.jpg", isDirectory: false, isSymbolicLink: false))
    XCTAssertFalse(MacJunkCleanup.isJunkItem(name: "._", isDirectory: false, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".Trashes", isDirectory: true, isSymbolicLink: false))
    XCTAssertFalse(MacJunkCleanup.isJunkItem(name: ".Trashes", isDirectory: false, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".Spotlight-V100", isDirectory: true, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".fseventsd", isDirectory: true, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".TemporaryItems", isDirectory: true, isSymbolicLink: false))
    XCTAssertTrue(MacJunkCleanup.isJunkItem(name: ".Trashes", isDirectory: false, isSymbolicLink: true))
    XCTAssertFalse(MacJunkCleanup.isProtectedName("photo.jpg"))
    XCTAssertTrue(MacJunkCleanup.isProtectedName("hiberfil.sys"))
    XCTAssertTrue(MacJunkCleanup.isProtectedName("HIBERFIL.SYS"))
    XCTAssertTrue(MacJunkCleanup.isProtectedName("pagefile.sys"))
    XCTAssertTrue(MacJunkCleanup.isProtectedName("swapfile.sys"))
    XCTAssertFalse(
      MacJunkCleanup.isJunkItem(name: "hiberfil.sys", isDirectory: false, isSymbolicLink: false)
    )
  }

  func testShouldRunDefaultOffAndSkipsInternalForceAndReadOnly() {
    XCTAssertFalse(MacJunkCleanup.defaultEnabled)
    let writable = shouldRun(enabled: true)
    XCTAssertTrue(writable)
    XCTAssertFalse(shouldRun(enabled: false))
    XCTAssertFalse(shouldRun(enabled: true, isInternal: true))
    XCTAssertFalse(shouldRun(enabled: true, isWritableFuse: false))
    XCTAssertFalse(shouldRun(enabled: true, mountPoint: ""))
    XCTAssertFalse(shouldRun(enabled: true, mountPoint: "/"))
    XCTAssertFalse(shouldRun(enabled: true, mountPoint: "/Volumes"))
    XCTAssertFalse(shouldRun(enabled: true, command: "mount"))
    XCTAssertFalse(shouldRun(enabled: true, isForce: true))
    XCTAssertTrue(shouldRun(enabled: true, command: "unmount"))
    XCTAssertFalse(MacJunkCleanup.isSafeMountPoint("/Users/someone"))
    XCTAssertTrue(MacJunkCleanup.isSafeMountPoint("/Volumes/My Passport"))
    XCTAssertTrue(MacJunkCleanup.isSafeMountPoint("/Volumes/移动硬盘"))
  }

  func testCleanFixtureRemovesJunkKeepsPhotoAndDoesNotFollowSymlinks() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(
      "ntfsmount-junk-\(UUID().uuidString)",
      isDirectory: true
    )
    let root = tmp.appendingPathComponent("My Passport", isDirectory: true)
    let photos = root.appendingPathComponent("照片", isDirectory: true)
    let outside = tmp.appendingPathComponent("outside-secret", isDirectory: true)
    defer { try? fm.removeItem(at: tmp) }

    try fm.createDirectory(at: photos, withIntermediateDirectories: true)
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    try "keep\n".write(to: photos.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)
    try "appledouble\n".write(
      to: photos.appendingPathComponent("._photo.jpg"),
      atomically: true,
      encoding: .utf8
    )
    try "ds\n".write(to: root.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
    try "ds\n".write(to: photos.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
    try "hiber\n".write(to: root.appendingPathComponent("hiberfil.sys"), atomically: true, encoding: .utf8)
    try "page\n".write(to: root.appendingPathComponent("pagefile.sys"), atomically: true, encoding: .utf8)
    try "secret\n".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    try "escaped-ds\n".write(
      to: outside.appendingPathComponent(".DS_Store"),
      atomically: true,
      encoding: .utf8
    )

    let trashes = root.appendingPathComponent(".Trashes", isDirectory: true)
    try fm.createDirectory(at: trashes, withIntermediateDirectories: true)
    try "trashed\n".write(to: trashes.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
    try fm.createDirectory(at: root.appendingPathComponent(".Spotlight-V100", isDirectory: true), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent(".fseventsd", isDirectory: true), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent(".TemporaryItems", isDirectory: true), withIntermediateDirectories: true)

    let appleDoubleDir = root.appendingPathComponent("._keepme", isDirectory: true)
    try fm.createDirectory(at: appleDoubleDir, withIntermediateDirectories: true)
    try "stay\n".write(to: appleDoubleDir.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)

    try fm.createSymbolicLink(
      at: root.appendingPathComponent("escape"),
      withDestinationURL: outside
    )
    try fm.createSymbolicLink(
      at: root.appendingPathComponent(".DS_Store.link"),
      withDestinationURL: photos.appendingPathComponent("photo.jpg")
    )
    // Junk-named symlink must not delete the off-tree target.
    try fm.createSymbolicLink(
      at: root.appendingPathComponent(".Trashes-link"),
      withDestinationURL: outside
    )

    let outcome = MacJunkCleanup.clean(at: root.path)
    XCTAssertTrue(outcome.failedPaths.isEmpty, "failed: \(outcome.failedPaths)")
    XCTAssertGreaterThanOrEqual(outcome.removedCount, 6)

    XCTAssertTrue(fm.fileExists(atPath: photos.appendingPathComponent("photo.jpg").path))
    XCTAssertFalse(fm.fileExists(atPath: photos.appendingPathComponent("._photo.jpg").path))
    XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(".DS_Store").path))
    XCTAssertFalse(fm.fileExists(atPath: photos.appendingPathComponent(".DS_Store").path))
    XCTAssertFalse(fm.fileExists(atPath: trashes.path))
    XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(".Spotlight-V100").path))
    XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(".fseventsd").path))
    XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(".TemporaryItems").path))
    XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("hiberfil.sys").path))
    XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("pagefile.sys").path))
    XCTAssertTrue(fm.fileExists(atPath: appleDoubleDir.appendingPathComponent("inside.txt").path))
    XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent("secret.txt").path))
    XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent(".DS_Store").path))
    XCTAssertTrue(fm.fileExists(atPath: photos.appendingPathComponent("photo.jpg").path))
  }

  func testCopyKeepsVolumeNameAndEnglishHasNoHan() {
    let en = Locale(identifier: "en")
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(MacJunkCleanup.Copy.failedTitle(locale: en), "Could not clean Mac junk files")
    XCTAssertTrue(MacJunkCleanup.Copy.failedBody(volumeName: "My Passport", locale: en).contains("My Passport"))
    XCTAssertTrue(MacJunkCleanup.Copy.failedBody(volumeName: "移动硬盘", locale: zh).contains("移动硬盘"))
    XCTAssertFalse(MacJunkCleanup.Copy.failedTitle(locale: en).contains("清理"))
    XCTAssertEqual(MacJunkCleanup.Copy.continueTitle(locale: zh), "不清理并继续")
  }

  private func shouldRun(
    enabled: Bool,
    isInternal: Bool = false,
    isWritableFuse: Bool = true,
    mountPoint: String = "/Volumes/My Passport",
    command: String = "eject",
    isForce: Bool = false
  ) -> Bool {
    MacJunkCleanup.shouldRun(
      enabled: enabled,
      isInternal: isInternal,
      isWritableFuse: isWritableFuse,
      mountPoint: mountPoint,
      command: command,
      isForce: isForce
    )
  }
}
