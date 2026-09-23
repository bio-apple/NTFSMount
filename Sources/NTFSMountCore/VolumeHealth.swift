import Foundation

public enum VolumeHealth {
  public static func looksDirtyOrHibernated(_ text: String) -> Bool {
    let t = text.lowercased()
    return t.contains("hibernat")
      || t.contains("hiberfile")
      || t.contains("unclean")
      || t.contains("not cleanly")
      || t.contains("unsafe state")
      || t.contains("windows cache")
      || t.contains("fast restart")
      || t.contains("volume is dirty")
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
    if success { return looksDirtyOrHibernated(helperOutput) ? .readOnlyDirty : .writable }
    if looksLikeKextOrFSKitBlock(helperOutput) { return .failedKext }
    if looksDirtyOrHibernated(helperOutput) { return .readOnlyDirty }
    return .failedOther
  }

  /// 菜单栏短状态：只读时区分系统 NTFS 与脏盘/休眠。
  public static func shortStatus(
    busy: Bool,
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    lastAdvice: MountAdvice?
  ) -> String {
    if busy { return "处理中" }
    if isWritableFuse { return "可写" }
    if isReadOnlyMounted {
      if lastAdvice == .readOnlyDirty { return "只读 · 休眠/未正常关机" }
      return "只读 · 系统 NTFS"
    }
    return "未挂载"
  }

  public static func detailStatus(
    isWritableFuse: Bool,
    isReadOnlyMounted: Bool,
    lastAdvice: MountAdvice?
  ) -> String {
    if isWritableFuse { return "已挂载（可读写）" }
    if lastAdvice == .readOnlyDirty {
      return "已挂载（只读）：Windows 休眠或卷不干净，请先在 Windows 彻底关机"
    }
    if isReadOnlyMounted {
      return "已挂载（只读）：系统 NTFS 驱动，可在下方改成可写（卷须干净）"
    }
    return "未挂载"
  }
}
