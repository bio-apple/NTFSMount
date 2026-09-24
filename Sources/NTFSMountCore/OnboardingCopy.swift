import Foundation

/// 首次启动确认框文案。回车是「同意并继续」；不同意请点「退出」或按 Esc。
public enum OnboardingCopy {
  public static let quitTitle = "退出"
  public static let agreeTitle = "同意并继续"
  public static let messageTitle = "使用前请确认"

  public static func body(notarized: Bool) -> String {
    var parts: [String] = []
    if !notarized {
      parts.append("""
      当前构建未公证。系统可能提示无法验证开发者：按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。
      仍被隔离时，终端执行：
      xattr -d com.apple.quarantine /Applications/NTFSMount.app
      然后再次打开。自己用可以继续；作为产品发给别人请先公证。
      """)
    }
    parts.append("""
    1. 以可写方式挂载或格式化 NTFS 可能损坏数据。请先备份。
    2. 捆绑的 FUSE-T go-nfsv4 不是 GPL，默认仅供个人使用。作为产品分发或销售前，须向 FUSE-T 取得书面许可（https://www.fuse-t.org/）。本安装包目前不是可公开再分发的产品。
    3. 本应用不联网、不收集账户。日志只写在本机。

    第一次使用请在窗口点「安装…」安装挂载助手。未公证包会请求管理员密码；已公证包优先用系统服务授权。

    回车即同意。不同意请点「退出」。
    """)
    return parts.joined(separator: "\n")
  }
}
