import AppKit
import NTFSMountCore
import SwiftUI

struct MenuRoot: View {
  @ObservedObject var store: VolumeStore

  var body: some View {
    Button("打开窗口") { store.showMainWindow() }
      .keyboardShortcut("o")
    Divider()
    if store.volumes.isEmpty {
      Text("没有检测到 NTFS 硬盘")
      Text(store.formatDisks.isEmpty
        ? "插入 Windows 格式的移动盘后再点菜单"
        : "可用窗口里「格式化为 NTFS」把其他移动盘转成 NTFS")
        .foregroundStyle(.secondary)
    } else {
      ForEach(store.volumes) { vol in
        Menu {
          if !vol.isWritableFuse {
            Button(vol.isInternal ? "以可写方式挂载（内置盘，需确认）" : "以可写方式挂载") {
              store.mount(vol)
            }
            .disabled(store.busyId != nil)
          }
          Button("在访达中打开") {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
          .disabled(vol.mountPoint.isEmpty)
          Divider()
          Button("卸载") { store.unmount(vol) }
            .disabled(vol.mountPoint.isEmpty || store.busyId != nil)
          Button("推出（可安全拔出）") { store.eject(vol) }
            .disabled(store.busyId != nil)
          Divider()
          Button("格式化为 NTFS…") {
            if let disk = store.formatDisks.first(where: { $0.id == wholeDiskId(vol.id) }) {
              store.confirmFormat(disk)
            }
          }
          .disabled(store.busyId != nil || !store.formatDisks.contains(where: { $0.id == wholeDiskId(vol.id) }))
        } label: {
          Text("\(store.statusLabel(vol))  ·  \(vol.name)  ·  \(vol.sizeLabel)")
        }
      }
      Divider()
      Button("全部以可写方式挂载") { store.mountAll() }
        .keyboardShortcut("m")
        .disabled(store.volumes.filter({ !$0.isInternal }).allSatisfy(\.isWritableFuse) || store.busyId != nil)
    }
    if !store.formatDisks.isEmpty {
      Divider()
      Menu("格式化为 NTFS…") {
        ForEach(store.formatDisks) { disk in
          Button("\(disk.name)  ·  \(disk.fsHint)  ·  \(disk.sizeLabel)") {
            store.confirmFormat(disk)
          }
          .disabled(store.busyId != nil)
        }
      }
    }
    Divider()
    Button("刷新") { store.refresh() }
      .keyboardShortcut("r")
    Button("设置…") { store.showSettings() }
    if !store.message.isEmpty {
      Text(store.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    Divider()
    Button("退出 NTFS 读写") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
