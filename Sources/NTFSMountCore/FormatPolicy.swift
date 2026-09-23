import Foundation

public enum FormatPolicy {
  public static let cancelTitle = "取消"
  public static let formatTitle = "抹掉并格式化"

  public static func confirms(typed: String, currentName: String) -> Bool {
    typed == currentName
  }

  public static func identityLines(
    sizeLabel: String,
    deviceId: String,
    serial: String,
    fsHint: String,
    mediaName: String
  ) -> String {
    var lines = ["容量：\(sizeLabel)", "设备：\(deviceId)"]
    if !mediaName.isEmpty { lines.append("介质：\(mediaName)") }
    lines.append("序列号：\(serial.isEmpty ? "未知" : serial)")
    if !fsHint.isEmpty { lines.append("当前格式：\(fsHint)") }
    return lines.joined(separator: "\n")
  }

  public static func finalWarning(
    name: String,
    sizeLabel: String,
    deviceId: String,
    serial: String
  ) -> String {
    let serialLine = serial.isEmpty ? "未知" : serial
    return "「\(name)」· \(sizeLabel) · \(deviceId)\n序列号：\(serialLine)\n将永久删除这张盘上的全部文件。"
  }

  public static func wholeDiskId(_ id: String) -> String {
    if let range = id.range(of: #"s\d"#, options: .regularExpression) {
      return String(id[..<range.lowerBound])
    }
    return id
  }

  public static func sanitizeLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed
      .replacingOccurrences(of: "/", with: "")
      .replacingOccurrences(of: "\"", with: "")
      .replacingOccurrences(of: "\\", with: "")
    let limited = String(cleaned.prefix(32))
    return limited.isEmpty ? "NTFS" : limited
  }
}

public func wholeDiskId(_ id: String) -> String {
  FormatPolicy.wholeDiskId(id)
}
