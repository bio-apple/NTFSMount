import Foundation

/// Manual GitHub Releases check (not Sparkle). Network fetch lives in the app target.
public enum GitHubReleaseUpdate {
  public static let latestReleaseAPIURL = URL(
    string: "https://api.github.com/repos/bio-apple/NTFSMount/releases/latest"
  )!
  public static let latestDMGURL = URL(
    string: "https://github.com/bio-apple/NTFSMount/releases/latest/download/NTFSMount.dmg"
  )!

  /// Strip a leading `v`/`V` and surrounding whitespace.
  public static func normalizeVersion(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.first == "v" || s.first == "V" {
      s = String(s.dropFirst())
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let a = versionComponents(lhs)
    let right = versionComponents(rhs)
    let n = max(a.count, right.count)
    for i in 0..<n {
      let x = i < a.count ? a[i] : 0
      let y = i < right.count ? right[i] : 0
      if x < y { return .orderedAscending }
      if x > y { return .orderedDescending }
    }
    return .orderedSame
  }

  public static func isRemoteNewer(current: String, remote: String) -> Bool {
    let cur = normalizeVersion(current)
    let rem = normalizeVersion(remote)
    guard !cur.isEmpty, !rem.isEmpty else { return false }
    return compare(cur, rem) == .orderedAscending
  }

  /// Prompt only when remote is newer than the installed app and not the version the user skipped.
  public static func shouldPrompt(current: String, remote: String, skipped: String?) -> Bool {
    guard isRemoteNewer(current: current, remote: remote) else { return false }
    if let skipped {
      let skip = normalizeVersion(skipped)
      let rem = normalizeVersion(remote)
      if !skip.isEmpty, compare(skip, rem) == .orderedSame { return false }
    }
    return true
  }

  /// Reads `tag_name` from GitHub `/releases/latest` JSON. Returns a normalized marketing version.
  public static func tagName(fromLatestReleaseJSON data: Data) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = obj["tag_name"] as? String
    else { return nil }
    let norm = normalizeVersion(tag)
    return norm.isEmpty ? nil : norm
  }

  private static func versionComponents(_ version: String) -> [Int] {
    let norm = normalizeVersion(version)
    guard !norm.isEmpty else { return [] }
    return norm.split(separator: ".").map { part in
      let digits = part.prefix(while: \.isNumber)
      return Int(digits) ?? 0
    }
  }
}
