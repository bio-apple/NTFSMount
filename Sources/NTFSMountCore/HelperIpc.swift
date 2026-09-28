import Foundation

/// Unix-socket argv for `ntfsmount-helperd`.
/// v1 was `v1 N\narg\n…` and could not carry `\n` in a volume label.
/// v2 is length-prefixed: `v2 N\nlen\n<bytes>…` (no JSON parser in the daemon).
public enum HelperIpc {
  public static let maxArgs = 32
  public static let maxArgBytes = 1024

  public static func encodeV2(_ args: [String]) -> Data? {
    guard (1...maxArgs).contains(args.count) else { return nil }
    var out = Data("v2 \(args.count)\n".utf8)
    for a in args {
      guard let bytes = a.data(using: .utf8), (0..<maxArgBytes).contains(bytes.count) else {
        return nil
      }
      out.append(contentsOf: Array("\(bytes.count)\n".utf8))
      out.append(bytes)
    }
    return out
  }

  /// Test/round-trip decoder. The daemon’s C parser is authoritative at runtime.
  public static func decodeV2(_ data: Data) -> [String]? {
    var i = data.startIndex
    func readLine() -> String? {
      guard let nl = data[i...].firstIndex(of: 0x0A) else { return nil }
      let line = String(data: data[i..<nl], encoding: .utf8)
      i = data.index(after: nl)
      return line
    }
    func readExact(_ n: Int) -> Data? {
      guard n >= 0, data.distance(from: i, to: data.endIndex) >= n else { return nil }
      let end = data.index(i, offsetBy: n)
      let slice = data[i..<end]
      i = end
      return Data(slice)
    }
    guard let header = readLine(), header.hasPrefix("v2 ") else { return nil }
    guard let argc = Int(header.dropFirst(3)), (1...maxArgs).contains(argc) else { return nil }
    var args: [String] = []
    args.reserveCapacity(argc)
    for _ in 0..<argc {
      guard let ls = readLine(), let n = Int(ls), (0..<maxArgBytes).contains(n) else { return nil }
      guard let bytes = readExact(n), !bytes.contains(0),
            let s = String(data: bytes, encoding: .utf8)
      else { return nil }
      args.append(s)
    }
    return args
  }

  /// Old daemons: newlines become spaces so the stream does not split.
  public static func encodeV1Compat(_ args: [String]) -> Data? {
    guard (1...maxArgs).contains(args.count) else { return nil }
    var payload = "v1 \(args.count)\n"
    for a in args {
      payload += a.replacingOccurrences(of: "\n", with: " ") + "\n"
    }
    return payload.data(using: .utf8)
  }

  /// format / ntfsfix on large disks can exceed a minute. Heartbeats keep a shorter SO_RCVTIMEO alive.
  public static func recvTimeoutSec(command: String) -> Int {
    switch command {
    case "format", "fix", "ntfsfix": return 600
    default: return 180
    }
  }

  /// Daemon writes NUL every 10s while the helper runs.
  public static func stripHeartbeats(_ data: Data) -> Data {
    if !data.contains(0) { return data }
    return Data(data.filter { $0 != 0 })
  }
}
