import Foundation

enum MacOSCompat {
  static let version = ProcessInfo.processInfo.operatingSystemVersion
  static var major: Int { version.majorVersion }
  static var isBelowMinimum: Bool { major < 13 }

  static var noticeBody: String {
    if isBelowMinimum {
      return "本应用仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，不支持 Intel Mac（x86_64）。当前系统低于 macOS 13，未测试，挂载可能失败。"
    }
    return "仅支持 Apple Silicon（M 芯片）与 macOS 13.0+，不支持 Intel Mac（x86_64）。"
      + "本应用不使用内核扩展。macOS 13 Ventura 起对 kext 限制更严，因此使用用户态 FUSE（ntfs-3g + FUSE-T）。"
      + "若提示 FSKit/模块未启用，可忽略——助手已优先使用 NFS/用户态路径，请勿安装内核扩展。"
  }
}
