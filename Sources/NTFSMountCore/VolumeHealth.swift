import Foundation

public enum VolumeHealth {
  public enum ProbeKind: Equatable, Sendable {
    case healthy
    case dirty
    case hibernated
    case corrupt
    case unknown
  }

  public enum PreMountDialog: Equatable, Sendable {
    case dirtyOrCorrupt
    case hibernated
  }

  public enum PreMountChoice: Equatable, Sendable {
    case readOnly
    case fixThenWritable
    case cancel
  }

  public static func looksHibernated(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("hibernat")
      || t.contains("hiberfile")
      || t.contains("hiberfil")
  }

  public static func looksDirty(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("unclean")
      || t.contains("not cleanly")
      || t.contains("unsafe state")
      || t.contains("windows cache")
      || t.contains("fast restart")
      || t.contains("volume is dirty")
  }

  public static func looksCorrupted(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("may be corrupt")
      || t.contains("volume is corrupt")
      || t.contains("ntfs volume is corrupt")
      || t.contains("failed to load $mft")
  }

  public static func looksClean(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("classify: volume is clean")
      || t.contains("processed successfully")
      || t.contains("mounting volume... ok")
  }

  public static func looksDirtyOrHibernated(_ text: String) -> Bool {
    looksHibernated(text) || looksDirty(text)
  }

  /// 仅脏卷/疑似损坏（未确认休眠文件）才允许提示 ntfsfix。休眠优先，避免破坏恢复数据。
  public static func canOfferDirtyFix(_ text: String) -> Bool {
    !looksHibernated(text) && (looksDirty(text) || looksCorrupted(text))
  }

  /// macOS `diskutil verifyVolume` 对 NTFS 弱、常需先卸载且可能卡住；
  /// 分类以 helper `ntfsfix -n` / dirty 旗标为准，不跑 `repairVolume`。
  public static func probeKind(from text: String) -> ProbeKind {
    let t = text.lowercased()
    if t.contains("classify: windows is hibernated") { return .hibernated }
    if t.contains("classify: volume may be corrupted") { return .corrupt }
    if t.contains("classify: volume is dirty") { return .dirty }
    if t.contains("classify: volume is clean") { return .healthy }
    if t.contains("classify: dirty/hibernation") { return .hibernated }
    if t.contains("classify: unknown") { return .unknown }
    if looksHibernated(text) { return .hibernated }
    if looksCorrupted(text) { return .corrupt }
    if looksDirty(text) { return .dirty }
    if looksClean(text) { return .healthy }
    return .unknown
  }

  /// 健康或探测失败（unknown）不弹吓人对话框。
  public static func preMountDialog(for kind: ProbeKind) -> PreMountDialog? {
    switch kind {
    case .healthy, .unknown: return nil
    case .dirty, .corrupt: return .dirtyOrCorrupt
    case .hibernated: return .hibernated
    }
  }

  public static func looksLikeKextOrFSKitBlock(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("fskit")
      || t.contains("kext")
      || t.contains("kernel extension")
      || t.contains("module is disabled")
      || t.contains("system extension")
      || text.contains("内核扩展")
  }

  public enum MountAdvice: Equatable {
    case writable
    case readOnlyDirty
    case failedKext
    case failedOther
  }

  public static func advice(for helperOutput: String, success: Bool) -> MountAdvice {
    if success { return looksDirtyOrHibernated(helperOutput) || looksCorrupted(helperOutput) ? .readOnlyDirty : .writable }
    if looksLikeKextOrFSKitBlock(helperOutput) { return .failedKext }
    if looksDirtyOrHibernated(helperOutput) || looksCorrupted(helperOutput) { return .readOnlyDirty }
    return .failedOther
  }

  /// 菜单栏短状态：只读时区分系统 NTFS 与脏盘/休眠。
  public static func shortStatus(
    busy: Bool,
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    lastAdvice: MountAdvice?,
    locale: Locale? = nil
  ) -> String {
    if busy { return L10n.t("status.busy", locale: locale) }
    if isWritableFuse { return L10n.t("status.writable", locale: locale) }
    if isReadOnlyMounted {
      if lastAdvice == .readOnlyDirty { return L10n.t("status.roDirty", locale: locale) }
      return L10n.t("status.roSystem", locale: locale)
    }
    return L10n.t("status.unmounted", locale: locale)
  }

  public static func detailStatus(
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    lastAdvice: MountAdvice?,
    locale: Locale? = nil
  ) -> String {
    if isWritableFuse { return L10n.t("status.detailWritable", locale: locale) }
    if lastAdvice == .readOnlyDirty {
      return L10n.t("status.detailDirty", locale: locale)
    }
    if isReadOnlyMounted {
      return L10n.t("status.detailRoSystem", locale: locale)
    }
    return L10n.t("status.unmounted", locale: locale)
  }

  /// Dirty Journal field: probe/classify only. Unknown until probe; never invent Yes/No.
  public static func journalLabel(
    probeKind: ProbeKind?,
    lastAdvice: MountAdvice?,
    helperText: String,
    locale: Locale? = nil
  ) -> String {
    if let probeKind {
      switch probeKind {
      case .healthy:
        return L10n.t("diskStatus.journalClean", locale: locale)
      case .dirty:
        return L10n.t("diskStatus.journalDirty", locale: locale)
      case .hibernated:
        return L10n.t("diskStatus.journalHibernated", locale: locale)
      case .corrupt:
        return L10n.t("diskStatus.journalCorrupt", locale: locale)
      case .unknown:
        break
      }
    }
    if lastAdvice == .readOnlyDirty {
      if looksHibernated(helperText) {
        return L10n.t("diskStatus.journalHibernated", locale: locale)
      }
      if looksDirty(helperText) {
        return L10n.t("diskStatus.journalDirty", locale: locale)
      }
      return L10n.t("status.roDirty", locale: locale)
    }
    return L10n.t("diskStatus.journalUnknown", locale: locale)
  }

  /// 挂载前健康对话框文案。回车默认「以只读挂载」。
  public enum PreMountCopy {
    public static var dirtyTitle: String { L10n.t("premount.dirtyTitle") }
    public static var hiberTitle: String { L10n.t("premount.hiberTitle") }
    public static var readOnlyTitle: String { L10n.t("premount.readOnly") }
    public static var fixThenWritableTitle: String { L10n.t("premount.fixThenWritable") }
    public static var cancelTitle: String { L10n.t("cancel") }
    public static var probingStatus: String { L10n.t("premount.probing") }

    public static func dirtyTitle(locale: Locale?) -> String {
      L10n.t("premount.dirtyTitle", locale: locale)
    }

    public static func hiberTitle(locale: Locale?) -> String {
      L10n.t("premount.hiberTitle", locale: locale)
    }

    public static func readOnlyTitle(locale: Locale?) -> String {
      L10n.t("premount.readOnly", locale: locale)
    }

    public static func fixThenWritableTitle(locale: Locale?) -> String {
      L10n.t("premount.fixThenWritable", locale: locale)
    }

    public static func cancelTitle(locale: Locale?) -> String {
      L10n.t("cancel", locale: locale)
    }

    public static func dirtyBody(volumeName: String, locale: Locale? = nil) -> String {
      L10n.format("premount.dirtyBody", volumeName, locale: locale)
    }

    public static func hiberBody(volumeName: String, locale: Locale? = nil) -> String {
      L10n.format("premount.hiberBody", volumeName, locale: locale)
    }
  }
}
