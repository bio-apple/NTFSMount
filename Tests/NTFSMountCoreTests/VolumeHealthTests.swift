import Foundation
import NTFSMountCore
import XCTest

final class VolumeHealthTests: XCTestCase {
  func testDirtyAndHibernationAreReadOnly() {
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("Windows is hibernated, refused to mount."))
    XCTAssertTrue(VolumeHealth.looksDirtyOrHibernated("hiberfil.sys present, unsafe state"))
    XCTAssertFalse(VolumeHealth.looksDirtyOrHibernated("Mounted successfully"))
    XCTAssertEqual(VolumeHealth.advice(for: "hibernated", success: true), .readOnlyDirty)
  }

  func testDistinguishesDirtyFromHibernated() {
    XCTAssertTrue(VolumeHealth.looksHibernated("Windows is hibernated, refused to mount."))
    XCTAssertTrue(VolumeHealth.looksHibernated("hiberfil.sys present"))
    XCTAssertFalse(VolumeHealth.looksHibernated("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirty("Volume is dirty. Please run chkdsk."))
    XCTAssertTrue(VolumeHealth.looksDirty("The disk contains an unclean file system"))
    XCTAssertTrue(VolumeHealth.looksDirty("Windows fast restart left the volume dirty"))
    XCTAssertFalse(VolumeHealth.looksDirty("Mounted successfully"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("volume is dirty"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("unclean / fast restart"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("Windows is hibernated"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("Volume is dirty. Windows is hibernated."))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("classify: volume is dirty"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("classify: volume may be corrupted"))
    XCTAssertTrue(VolumeHealth.canOfferDirtyFix("NTFS volume may be corrupted"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: Windows is hibernated"))
    XCTAssertFalse(VolumeHealth.canOfferDirtyFix("classify: dirty/hibernation"))
  }

  func testPreMountProbeClassificationAndCopy() {
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume is clean"), .healthy)
    XCTAssertEqual(VolumeHealth.probeKind(from: "NTFS partition processed successfully."), .healthy)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume is dirty"), .dirty)
    XCTAssertEqual(VolumeHealth.probeKind(from: "The disk contains an unclean file system"), .dirty)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: Windows is hibernated"), .hibernated)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: volume may be corrupted"), .corrupt)
    XCTAssertEqual(VolumeHealth.probeKind(from: "NTFS volume may be corrupted"), .corrupt)
    XCTAssertEqual(VolumeHealth.probeKind(from: "classify: unknown"), .unknown)
    XCTAssertEqual(VolumeHealth.probeKind(from: "Mounted successfully"), .unknown)
    XCTAssertEqual(
      VolumeHealth.probeKind(from: "unclean file system. NTFS partition was processed successfully."),
      .dirty
    )
    XCTAssertEqual(
      VolumeHealth.probeKind(from: "Volume is dirty. Windows is hibernated."),
      .hibernated
    )

    XCTAssertNil(VolumeHealth.preMountDialog(for: .healthy))
    XCTAssertNil(VolumeHealth.preMountDialog(for: .unknown))
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .dirty), .dirtyOrCorrupt)
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .corrupt), .dirtyOrCorrupt)
    XCTAssertEqual(VolumeHealth.preMountDialog(for: .hibernated), .hibernated)

    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(VolumeHealth.PreMountCopy.dirtyTitle(locale: zh), "NTFS 卷可能已损坏/未正常卸载")
    XCTAssertEqual(VolumeHealth.PreMountCopy.readOnlyTitle(locale: zh), "以只读挂载")
    XCTAssertEqual(VolumeHealth.PreMountCopy.fixThenWritableTitle(locale: zh), "尝试修复后可写")
    XCTAssertEqual(VolumeHealth.PreMountCopy.cancelTitle(locale: zh), "取消")
    XCTAssertEqual(VolumeHealth.PreMountCopy.hiberTitle(locale: zh), "检测到 Windows 休眠")
    let dirtyBody = VolumeHealth.PreMountCopy.dirtyBody(volumeName: "BANDISK", locale: zh)
    XCTAssertTrue(dirtyBody.contains("BANDISK"))
    XCTAssertTrue(dirtyBody.contains("未正常卸载") || dirtyBody.contains("损坏"))
    XCTAssertTrue(dirtyBody.contains("ntfsfix"))
    XCTAssertFalse(dirtyBody.contains("repairVolume"))
    let hiberBody = VolumeHealth.PreMountCopy.hiberBody(volumeName: "WIN", locale: zh)
    XCTAssertTrue(hiberBody.contains("WIN"))
    XCTAssertTrue(hiberBody.contains("彻底关机"))
    XCTAssertTrue(hiberBody.contains("只读"))
    XCTAssertTrue(hiberBody.contains("不会运行 ntfsfix"))
    XCTAssertFalse(hiberBody.contains("尝试修复后可写"))
  }

  func testKextBlockIsClassified() {
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("FSKit module is disabled"))
    XCTAssertTrue(VolumeHealth.looksLikeKextOrFSKitBlock("kernel extension denied"))
    XCTAssertEqual(VolumeHealth.advice(for: "fskit unavailable", success: false), .failedKext)
  }

  func testReadOnlyStatusExplainsCause() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      VolumeHealth.shortStatus(
        busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: nil, locale: zh
      ),
      "只读 · 系统 NTFS"
    )
    XCTAssertEqual(
      VolumeHealth.shortStatus(
        busy: false, isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty, locale: zh
      ),
      "只读 · 休眠/未正常关机"
    )
    XCTAssertTrue(
      VolumeHealth.detailStatus(
        isWritableFuse: false, isReadOnlyMounted: true, lastAdvice: .readOnlyDirty, locale: zh
      )
      .contains("彻底关机")
    )
    XCTAssertEqual(
      VolumeHealth.detailStatus(
        isWritableFuse: false, isReadOnlyMounted: false, lastAdvice: .readOnlyDirty, locale: zh
      ),
      "未挂载：Windows 休眠或卷不干净，请先在 Windows 彻底关机"
    )
    XCTAssertFalse(
      VolumeHealth.detailStatus(
        isWritableFuse: false, isReadOnlyMounted: false, lastAdvice: .readOnlyDirty, locale: zh
      ).contains("已挂载")
    )
  }

  func testJournalLabelStaysUnknownUntilProbeAndNeverYesNo() {
    let zh = Locale(identifier: "zh-Hans")
    XCTAssertEqual(
      VolumeHealth.journalLabel(probeKind: nil, lastAdvice: nil, helperText: "", locale: zh),
      "未知"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: nil, lastAdvice: .writable, helperText: "OK\nrw\n", locale: zh
      ),
      "未知"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .dirty, lastAdvice: .readOnlyDirty, helperText: "classify: volume is dirty", locale: zh
      ),
      "脏卷"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .hibernated, lastAdvice: .readOnlyDirty,
        helperText: "classify: Windows is hibernated", locale: zh
      ),
      "休眠"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: .healthy, lastAdvice: .writable, helperText: "classify: volume is clean", locale: zh
      ),
      "未见脏卷标记"
    )
    XCTAssertEqual(
      VolumeHealth.journalLabel(
        probeKind: nil, lastAdvice: .readOnlyDirty, helperText: "Windows is hibernated", locale: zh
      ),
      "休眠"
    )
    let fallback = VolumeHealth.journalLabel(
      probeKind: .unknown, lastAdvice: .readOnlyDirty, helperText: "", locale: zh
    )
    XCTAssertEqual(fallback, "只读 · 休眠/未正常关机")
    XCTAssertFalse(fallback == "Yes" || fallback == "No")
  }
}
