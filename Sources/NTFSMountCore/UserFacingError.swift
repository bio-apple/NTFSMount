import Foundation

public enum UserFacingError {
  public static func message(from raw: String, logPath: String? = nil) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "操作失败，请查看日志。" }
    let lower = t.lowercased()
    if lower.contains("user canceled") || t.contains("-128") || lower.contains("(-128)") {
      return "已取消。"
    }
    if lower.contains("no such file") || t.contains("(127)") || lower.contains("not found") {
      return "安装助手失败，请再试一次。详情已写入日志。"
    }
    if lower.contains("execution error") || lower.contains("osascript") || lower.contains("0:") {
      return "未能取得管理员权限。若刚才点了取消，可再试。详情已写入日志。"
    }
    if lower.contains("password") && lower.contains("sudo") {
      return "挂载助手需要更新。请在窗口点「更新…」。"
    }
    if t.hasPrefix("error:") {
      return String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
    }
    if t.count > 180 {
      if let logPath {
        return "操作失败。详情已写入 \(logPath)"
      }
      return "操作失败。详情已写入日志。"
    }
    return t
  }
}
