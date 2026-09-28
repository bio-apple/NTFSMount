import Foundation
import NTFSMountCore

enum MacOSCompat {
  static let version = ProcessInfo.processInfo.operatingSystemVersion
  static var major: Int { version.majorVersion }
  static var isBelowMinimum: Bool { major < 13 }

  static var noticeBody: String {
    if isBelowMinimum {
      return L10n.t("compat.belowMin")
    }
    return L10n.t("compat.ok")
  }
}
