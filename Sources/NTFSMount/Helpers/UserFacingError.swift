import NTFSMountCore

/// 文案映射在 NTFSMountCore，便于单测。应用侧加上日志路径。
enum AppErrors {
  static func message(_ raw: String) -> String {
    UserFacingError.message(from: raw, logPath: AppLog.url.path)
  }
}
