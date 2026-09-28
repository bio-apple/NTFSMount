import Foundation

/// Locate a system binary without hardcoding `/bin` vs `/usr/bin` (these move across macOS).
/// Privileged callers must not search `PATH` (hijack). Only well-known system directories.
public enum CommandPath {
  public static let systemDirs = ["/bin", "/usr/bin", "/sbin", "/usr/sbin"]

  /// `name` is a basename (`launchctl`) or an absolute path already.
  public static func find(_ name: String) -> String? {
    let fm = FileManager.default
    if name.contains("/") {
      return fm.isExecutableFile(atPath: name) ? name : nil
    }
    for dir in systemDirs {
      let candidate = (dir as NSString).appendingPathComponent(name)
      if fm.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }
}
