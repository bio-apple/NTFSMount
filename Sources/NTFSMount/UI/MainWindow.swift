import AppKit
import NTFSMountCore
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
  static let shared = MainWindowController()
  private var window: NSWindow?

  func show(store: VolumeStore) {
    if window == nil {
      let hosting = NSHostingController(rootView: MainWindowView(store: store))
      let win = NSWindow(contentViewController: hosting)
      win.title = "NTFS 读写"
      win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      win.toolbarStyle = .unified
      win.setContentSize(NSSize(width: 840, height: 540))
      win.minSize = NSSize(width: 680, height: 400)
      win.center()
      win.isReleasedWhenClosed = false
      win.setFrameAutosaveName("NTFSMount.MainWindow")
      win.delegate = self
      window = win
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    DispatchQueue.main.async {
      if UserDefaults.standard.bool(forKey: AppIdentity.Defaults.showDock) {
        NSApp.setActivationPolicy(.regular)
      } else {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }
}

enum LogViewer {
  static func open() {
    let paths = [
      NSHomeDirectory() + "/Library/Logs/ntfsmount.log",
      "/tmp/ntfsmount.log",
      "/tmp/ntfs-rw.log",
      "/var/log/ntfsmount.log",
    ]
    if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
      NSWorkspace.shared.open(URL(fileURLWithPath: path))
      return
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
  }
}

struct MainWindowView: View {
  @ObservedObject var store: VolumeStore
  @State private var selectedId: String?

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 196, ideal: 228, max: 300)
    } detail: {
      detail
    }
    .frame(minWidth: 680, minHeight: 400)
    .onAppear {
      if store.openSettings {
        selectedId = "__settings__"
        store.openSettings = false
      } else {
        reconcileSelection(store.volumes)
      }
    }
    .onChange(of: store.volumes) { vols in
      if selectedId != "__settings__" {
        reconcileSelection(vols)
      }
    }
    .onChange(of: store.openSettings) { want in
      if want {
        selectedId = "__settings__"
        store.openSettings = false
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          store.refresh()
        } label: {
          Label("刷新", systemImage: "arrow.clockwise")
        }
        .help("刷新磁盘列表")
      }
      ToolbarItem(placement: .automatic) {
        Button {
          LogViewer.open()
        } label: {
          Label("查看日志", systemImage: "doc.text")
        }
        .help("打开本机挂载日志")
      }
      ToolbarItem(placement: .automatic) {
        Button {
          store.showAbout()
        } label: {
          Label("关于", systemImage: "info.circle")
        }
      }
    }
  }

  private var sidebar: some View {
    List(selection: $selectedId) {
      Section("设备") {
        if store.volumes.isEmpty {
          Text("没有 NTFS 磁盘")
            .foregroundStyle(.secondary)
        }
        ForEach(store.volumes) { vol in
          VolumeSidebarRow(store: store, vol: vol, busy: store.busyId == vol.id)
            .tag(vol.id)
        }
      }
      Section {
        Label("设置", systemImage: "gearshape")
          .tag("__settings__")
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("NTFS 读写")
  }

  @ViewBuilder
  private var detail: some View {
    if selectedId == "__settings__" {
      SettingsView(store: store)
    } else if let vol = store.volumes.first(where: { $0.id == selectedId }) {
      VolumeDetailView(store: store, vol: vol)
    } else {
      EmptyVolumeView(store: store)
    }
  }

  private func reconcileSelection(_ vols: [NTFSVolume]) {
    if let selectedId, vols.contains(where: { $0.id == selectedId }) { return }
    selectedId = vols.first?.id
  }
}

private struct VolumeSidebarRow: View {
  @ObservedObject var store: VolumeStore
  let vol: NTFSVolume
  let busy: Bool

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(vol.name)
          .lineLimit(1)
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    } icon: {
      if busy {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: vol.isWritableFuse ? "externaldrive.fill" : "externaldrive")
          .foregroundStyle(vol.isWritableFuse ? Color.accentColor : Color.secondary)
          .symbolRenderingMode(.hierarchical)
      }
    }
  }

  private var caption: String {
    store.statusLabel(vol)
  }
}

private struct EmptyVolumeView: View {
  @ObservedObject var store: VolumeStore

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "externaldrive.badge.questionmark")
        .font(.system(size: 48))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
      Text("没有检测到 NTFS 硬盘")
        .font(.title3.weight(.semibold))
      Text(store.formatDisks.isEmpty
        ? "插入 Windows 格式的移动盘后会出现在左侧。"
        : "其他移动盘可通过「格式化为 NTFS」转换。设置在左侧底部。")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      Button("刷新") { store.refresh() }
        .controlSize(.large)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

private struct VolumeDetailView: View {
  @ObservedObject var store: VolumeStore
  let vol: NTFSVolume

  private var busy: Bool { store.busyId == vol.id }
  private var formatDisk: FormatDisk? {
    store.formatDisks.first(where: { $0.id == wholeDiskId(vol.id) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !store.helperInstalled {
        helperBanner(
          text: "第一次使用需要安装挂载助手。",
          button: "安装…",
          action: { store.installHelper() }
        )
      } else if Privileged.helperNeedsUpdate {
        helperBanner(
          text: "挂载助手需要更新后才能使用全部功能。",
          button: "更新…",
          action: { store.installHelper() }
        )
      }

      VStack(alignment: .leading, spacing: 20) {
        header
        if vol.hasUsage {
          CapacityBar(used: vol.usedBytes, free: vol.freeBytes)
        }
        properties
        if !store.message.isEmpty {
          Text(store.message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        Spacer(minLength: 12)
        actions
      }
      .padding(28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(spacing: 6) {
        Image(systemName: "externaldrive.fill")
          .font(.system(size: 44))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.secondary)
        Text("NTFS")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .frame(width: 76)

      VStack(alignment: .leading, spacing: 5) {
        Text(vol.name)
          .font(.title2.weight(.semibold))
        if !vol.mediaName.isEmpty {
          Text(vol.mediaName)
            .foregroundStyle(.secondary)
        }
        statusLine
        if !vol.mountPoint.isEmpty {
          Text(vol.expectedMountPoint)
            .font(.body)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      Spacer(minLength: 0)
      if busy {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var statusLine: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
        Text(store.detailStatus(vol))
        .font(.subheadline.weight(.medium))
        .foregroundStyle(statusColor)
    }
  }

  private var statusColor: Color {
    if vol.isWritableFuse { return Color(nsColor: .systemGreen) }
    if vol.isReadOnlyMounted { return Color(nsColor: .systemOrange) }
    return Color.secondary
  }

  private var properties: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
      GridRow {
        Text("容量")
          .foregroundStyle(.secondary)
          .gridColumnAlignment(.trailing)
        Text(vol.sizeLabel)
      }
      GridRow {
        Text("文件系统")
          .foregroundStyle(.secondary)
          .gridColumnAlignment(.trailing)
        Text("NTFS")
      }
    }
    .font(.body)
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        if vol.isWritableFuse {
          Button("卸载") { store.unmount(vol) }
            .buttonStyle(.borderedProminent)
        } else {
          Button("以可写方式挂载") { store.mount(vol) }
            .buttonStyle(.borderedProminent)
        }

        Button("推出（可安全拔出）") { store.eject(vol) }
          .buttonStyle(.bordered)

        Button("在访达中打开") {
          NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
        }
        .buttonStyle(.bordered)
        .disabled(vol.mountPoint.isEmpty)
      }
      .controlSize(.large)

      HStack(spacing: 10) {
        Button("查看日志") { LogViewer.open() }
          .buttonStyle(.bordered)
        Button("关于与隐私") { store.showAbout() }
          .buttonStyle(.bordered)
        Spacer(minLength: 8)
        if let disk = formatDisk {
          Button("格式化为 NTFS…", role: .destructive) {
            store.confirmFormat(disk)
          }
          .buttonStyle(.bordered)
        }
      }
      .controlSize(.regular)
    }
    .disabled(busy)
  }

  private func helperBanner(text: String, button: String, action: @escaping () -> Void) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color(nsColor: .systemOrange))
      Text(text)
      Spacer()
      Button(button, action: action)
        .controlSize(.small)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(nsColor: .controlBackgroundColor))
  }
}

private struct CapacityBar: View {
  let used: Int64
  let free: Int64

  var body: some View {
    let total = used + free
    let ratio = total > 0 ? min(1, Double(used) / Double(total)) : 0
    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(Color(nsColor: .separatorColor).opacity(0.35))
          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(Color(nsColor: .systemBlue))
            .frame(width: geo.size.width * ratio)
        }
      }
      .frame(height: 11)
      HStack {
        Text("已用 \(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))")
        Spacer()
        Text("可用 \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}
