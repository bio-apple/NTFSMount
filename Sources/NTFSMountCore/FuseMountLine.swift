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

  public static func mountPoint(from line: String) -> String? {
    guard let on = line.range(of: " on "),
          let end = line.range(of: " (")
    else { return nil }
    guard on.upperBound < end.lowerBound else { return nil }
    let mp = String(line[on.upperBound..<end.lowerBound])
    return mp.isEmpty ? nil : mp
  }

  public static func fuseMountPoints(fromMountOutput text: String) -> Set<String> {
    var fuse = Set<String>()
    for raw in text.split(separator: "\n") {
      let line = String(raw)
      guard isOurFuseMount(line), let mp = mountPoint(from: line) else { continue }
      fuse.insert(mp)
    }
    return fuse
  }
}
