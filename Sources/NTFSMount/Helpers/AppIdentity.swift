import CryptoKit
import Foundation

enum AppIdentity {
  static let productName = "NTFS 读写"
  static let bundleId = "com.bioapple.ntfsmount"
  static let helperVersion = "5"
  static let sourceURL = "https://github.com/bio-apple/NTFSMount"
  static let helperSocket = "/var/run/com.bioapple.ntfsmount.sock"
  static let helperDaemonPath = "/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd"
  static let helperSupportPath = "/Library/Application Support/NTFSMount/ntfs-rw-helper"
  static let helperStampPath = "/Library/Application Support/NTFSMount/helper.stamp"
  static let appPathFile = "/Library/Application Support/NTFSMount/app.path"
  static let legacyHelperPath = "/usr/local/sbin/ntfs-rw-helper"
  static let legacySudoers = "/etc/sudoers.d/ntfs-rw"
  static let daemonPlist = "/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist"
  static let helperDaemonPlist = "/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist"
  static let legacyDaemonPlist = "/Library/LaunchDaemons/local.ntfsmount.automount.plist"

  enum Defaults {
    static let autoMountUserOff = "com.bioapple.ntfsmount.autoMountUserOff"
    static let showDock = "com.bioapple.ntfsmount.showDock"
    static let didShowWindow = "com.bioapple.ntfsmount.didShowWindow"
    static let didShowCompat = "com.bioapple.ntfsmount.didShowCompatNotice"
    static let didMigrate = "com.bioapple.ntfsmount.didMigrateDefaults"
    static let didAcceptLegal = "com.bioapple.ntfsmount.didAcceptLegal"
    static let didAcceptWritable = "com.bioapple.ntfsmount.didAcceptWritable"
    static let didShowGatekeeper = "com.bioapple.ntfsmount.didShowGatekeeper"
    static let lastHelperSHA = "com.bioapple.ntfsmount.lastHelperSHA"
  }

  static func migrateDefaultsIfNeeded() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: Defaults.didMigrate) else { return }
    let map = [
      "local.ntfsmount.autoMountUserOff": Defaults.autoMountUserOff,
      "local.ntfsmount.didShowCompatNotice": Defaults.didShowCompat,
    ]
    for (old, new) in map where d.object(forKey: new) == nil && d.object(forKey: old) != nil {
      d.set(d.object(forKey: old), forKey: new)
    }
    d.set(true, forKey: Defaults.didMigrate)
  }

  static var writableStampURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/com.bioapple.ntfsmount/writable-accepted")
  }

  static func markWritableAccepted() {
    UserDefaults.standard.set(true, forKey: Defaults.didAcceptWritable)
    let url = writableStampURL
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "1\n".write(to: url, atomically: true, encoding: .utf8)
  }

  static func sha256File(_ path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
