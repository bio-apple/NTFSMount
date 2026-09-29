import Foundation

/// Parses `mount(8)` lines the same way the helper's `is_our_fuse_mount` does,
/// including FUSE-T NFSv4 mounts that only show `(nfs,` with no "fuse" token.
public enum FuseMountLine {
  public static func isOurFuseMount(_ line: String) -> Bool {
    let lower = line.lowercased()
    return lower.contains("macfuse")
      || lower.contains("osxfuse")
      || lower.contains("fuse-t")
      || lower.contains("fuset")
      || lower.contains("ntfs-3g")
      || line.contains(" fuse,")
      || lower.contains("(nfs,")
      || lower.contains(" (nfs,")
      || lower.contains("smbfs")
  }

  /// `mount(8)` prints `read-only` in the option list for a read-only mount. Being *our* FUSE
  /// mount says nothing about writability: a dirty volume mounts read-only through ntfs-3g too.
  public static func isReadOnly(_ line: String) -> Bool {
    line.lowercased().contains("read-only")
  }

  /// Mount point → whether it is mounted read-only.
  public static func fuseMountStates(fromMountOutput text: String) -> [String: Bool] {
    var out: [String: Bool] = [:]
    for raw in text.split(separator: "\n") {
      let line = String(raw)
      guard isOurFuseMount(line), let mp = mountPoint(from: line) else { continue }
      out[mp] = isReadOnly(line)
    }
    return out
  }

  public static func mountPoint(from line: String) -> String? {
    guard let on = line.range(of: " on "),
          let end = line.range(of: " (")
    else { return nil }
    guard on.upperBound < end.lowerBound else { return nil }
    let mp = String(line[on.upperBound..<end.lowerBound])
    return mp.isEmpty ? nil : mp
  }

  public static func fuseMountPoints(fromMountOutput text: String) -> Set<String> {
    Set(fuseMountStates(fromMountOutput: text).keys)
  }
}
