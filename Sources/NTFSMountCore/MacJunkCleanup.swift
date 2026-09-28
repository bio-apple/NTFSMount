import Darwin
import Foundation

/// Optional pre-eject / pre-unmount removal of macOS hidden junk on a mounted NTFS tree.
/// Runs as the GUI user via FileManager (no root helper wipe, no format, no ntfsfix).
public enum MacJunkCleanup {
  public static let defaultEnabled = false

  public static let junkDirectoryNames: Set<String> = [
    ".Trashes",
    ".Spotlight-V100",
    ".fseventsd",
    ".TemporaryItems",
  ]

  public struct Outcome: Equatable, Sendable {
    public var removedCount: Int
    public var failedPaths: [String]

    public init(removedCount: Int = 0, failedPaths: [String] = []) {
      self.removedCount = removedCount
      self.failedPaths = failedPaths
    }
  }

  /// Default-off. External writable FUSE NTFS only. Never on force-unmount, internals, or empty mounts.
  public static func shouldRun(
    enabled: Bool,
    isInternal: Bool,
    isWritableFuse: Bool,
    mountPoint: String,
    command: String,
    isForce: Bool
  ) -> Bool {
    guard enabled, !isInternal, isWritableFuse, !isForce else { return false }
    guard command == "eject" || command == "unmount" else { return false }
    return isSafeMountPoint(mountPoint)
  }

  public static func isSafeMountPoint(_ mountPoint: String) -> Bool {
    let path = (mountPoint as NSString).standardizingPath
    guard path.hasPrefix("/Volumes/"), path != "/Volumes" else { return false }
    return isAllowedCleanupRoot(path)
  }

  /// File matcher: `.DS_Store` files, AppleDouble `._*` files (not directories), junk directories.
  public static func isJunkItem(name: String, isDirectory: Bool, isSymbolicLink: Bool) -> Bool {
    if name.isEmpty || name == "." || name == ".." { return false }
    if isProtectedName(name) { return false }
    if isSymbolicLink {
      if isJunkFileName(name) { return true }
      return junkDirectoryNames.contains(name)
    }
    if isDirectory { return junkDirectoryNames.contains(name) }
    return isJunkFileName(name)
  }

  public static func isProtectedName(_ name: String) -> Bool {
    switch name.lowercased() {
    case "hiberfil.sys", "pagefile.sys", "swapfile.sys":
      return true
    default:
      return false
    }
  }

  /// Walk `root` without following directory symlinks off the tree. Temp-dir tests call this directly.
  public static func clean(at root: String) -> Outcome {
    let fm = FileManager.default
    let standardized = (root as NSString).standardizingPath
    guard isAllowedCleanupRoot(standardized) else {
      return Outcome(failedPaths: [root])
    }
    var rootSt = stat()
    guard lstat(standardized, &rootSt) == 0, (rootSt.st_mode & S_IFMT) == S_IFDIR else {
      return Outcome()
    }
    var targets: [URL] = []
    collect(
      path: standardized,
      rootPath: standardized,
      rootDev: rootSt.st_dev,
      into: &targets
    )
    targets.sort { $0.path.count > $1.path.count }
    var removed = 0
    var failed: [String] = []
    for url in targets {
      guard isInsideRoot(url, rootPath: standardized) else { continue }
      do {
        try fm.removeItem(at: url)
        removed += 1
      } catch {
        failed.append(url.path)
      }
    }
    return Outcome(removedCount: removed, failedPaths: failed)
  }

  public enum Copy {
    public static func failedTitle(locale: Locale? = nil) -> String {
      L10n.t("cleanJunk.failedTitle", locale: locale)
    }

    public static func failedBody(volumeName: String, locale: Locale? = nil) -> String {
      L10n.format("cleanJunk.failedBody", volumeName, locale: locale)
    }

    public static func continueTitle(locale: Locale? = nil) -> String {
      L10n.t("cleanJunk.continueWithout", locale: locale)
    }
  }

  private static let bannedRoots: Set<String> = [
    "/", "/Volumes", "/System", "/Library", "/Users", "/Applications",
    "/private", "/usr", "/bin", "/sbin", "/dev", "/tmp", "/var",
    "/System/Volumes/Data",
  ]

  private static func isJunkFileName(_ name: String) -> Bool {
    if name == ".DS_Store" { return true }
    return name.hasPrefix("._") && name.count > 2
  }

  private static func collect(
    path: String,
    rootPath: String,
    rootDev: dev_t,
    into targets: inout [URL]
  ) {
    guard let names = posixDirectoryNames(path) else { return }
    for name in names {
      if name == "." || name == ".." { continue }
      let fullPath = (path as NSString).appendingPathComponent(name)
      let item = URL(fileURLWithPath: fullPath)
      guard isInsideRoot(item, rootPath: rootPath) else { continue }
      var st = stat()
      guard lstat(fullPath, &st) == 0 else { continue }
      if st.st_dev != rootDev { continue }
      let isLink = (st.st_mode & S_IFMT) == S_IFLNK
      let isDir = (st.st_mode & S_IFMT) == S_IFDIR && !isLink
      if isJunkItem(name: name, isDirectory: isDir, isSymbolicLink: isLink) {
        targets.append(item)
        continue
      }
      if isLink { continue }
      if isDir {
        collect(path: fullPath, rootPath: rootPath, rootDev: rootDev, into: &targets)
      }
    }
  }

  /// `FileManager.contentsOfDirectory` hides AppleDouble `._*` names; readdir does not.
  private static func posixDirectoryNames(_ path: String) -> [String]? {
    guard let dir = opendir(path) else { return nil }
    defer { closedir(dir) }
    var names: [String] = []
    while let ent = readdir(dir) {
      let name = withUnsafeBytes(of: ent.pointee.d_name) { raw -> String? in
        raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) }
      }
      guard let name, name != ".", name != ".." else { continue }
      names.append(name)
    }
    return names
  }

  private static func isAllowedCleanupRoot(_ path: String) -> Bool {
    guard !path.isEmpty, !bannedRoots.contains(path) else { return false }
    let parts = URL(fileURLWithPath: path).pathComponents
    return parts.count >= 3
  }

  private static func isInsideRoot(_ url: URL, rootPath: String) -> Bool {
    let path = (url.path as NSString).standardizingPath
    if path == rootPath { return false }
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return path.hasPrefix(prefix)
  }
}
