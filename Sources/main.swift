import AppKit
import ServiceManagement
import SwiftUI

@main
struct NTFSMountApp: App {
  @StateObject private var store = VolumeStore()

  var body: some Scene {
    MenuBarExtra {
      MenuRoot(store: store)
    } label: {
      Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
    }
    .menuBarExtraStyle(.menu)
  }
}

@MainActor
final class VolumeStore: ObservableObject {
  @Published var volumes: [NTFSVolume] = []
  @Published var message: String = ""
  @Published var busyId: String?
  @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

  private var timer: Timer?

  var writableCount: Int { volumes.filter(\.isWritableFuse).count }
  var menuBarTitle: String {
    if volumes.isEmpty { return "NTFS" }
    if writableCount > 0 { return "NTFS \(writableCount)" }
    return "NTFS"
  }

  var menuBarSymbol: String {
    if writableCount > 0 { return "externaldrive.fill.badge.checkmark" }
    if volumes.contains(where: { !$0.mountPoint.isEmpty }) { return "externaldrive.fill.badge.questionmark" }
    if !volumes.isEmpty { return "externaldrive" }
    return "externaldrive.badge.questionmark"
  }

  init() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    volumes = NTFSVolume.scan()
  }

  func mount(_ vol: NTFSVolume) {
    run("mount", vol)
  }

  func unmount(_ vol: NTFSVolume) {
    run("unmount", vol)
  }

  func eject(_ vol: NTFSVolume) {
    run("eject", vol)
  }

  func mountAll() {
    for vol in volumes where !vol.isWritableFuse {
      run("mount", vol)
    }
  }

  func toggleLogin() {
    do {
      if launchAtLogin {
        try SMAppService.mainApp.unregister()
        launchAtLogin = false
      } else {
        try SMAppService.mainApp.register()
        launchAtLogin = true
      }
    } catch {
      message = "开机启动失败：\(error.localizedDescription)"
    }
  }

  private func run(_ cmd: String, _ vol: NTFSVolume) {
    busyId = vol.id
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Privileged.run(cmd, vol.id)
      DispatchQueue.main.async {
        self.busyId = nil
        if result.ok {
          self.message = result.text
          self.refresh()
          if cmd == "mount" {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
        } else {
          self.message = result.text
          self.refresh()
        }
      }
    }
  }
}

struct NTFSVolume: Identifiable, Equatable {
  let id: String
  let name: String
  let size: Int64
  let mountPoint: String
  let isWritableFuse: Bool
  let isReadOnlyMounted: Bool

  var expectedMountPoint: String { mountPoint.isEmpty ? "/Volumes/\(name)" : mountPoint }

  var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  var stateLabel: String {
    if isWritableFuse { return "可写" }
    if isReadOnlyMounted { return "系统只读" }
    return "未挂载"
  }

  static func scan() -> [NTFSVolume] {
    guard let list = diskutilPlist(["list", "-plist"]) else { return [] }
    let disks = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
    var ids: [String] = []
    for disk in disks {
      for part in disk["Partitions"] as? [[String: Any]] ?? [] {
        if let ident = part["DeviceIdentifier"] as? String {
          ids.append(ident)
        }
      }
      if let ident = disk["DeviceIdentifier"] as? String,
         disk["Partitions"] == nil {
        ids.append(ident)
      }
    }

    let mountTable = currentMounts()

    var out: [NTFSVolume] = []
    for ident in ids {
      guard let info = diskutilPlist(["info", "-plist", ident]) else { continue }
      let fs = info["FilesystemName"] as? String ?? ""
      guard fs == "NTFS" else { continue }
      let name = info["VolumeName"] as? String
      let volumeName = (name?.isEmpty == false) ? name! : "NTFS-\(ident)"
      let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? 0
      let diskutilMp = info["MountPoint"] as? String ?? ""
      let expected = "/Volumes/\(volumeName)"
      let fuseMp = mountTable.fusePoints.contains(diskutilMp) ? diskutilMp
        : (mountTable.fusePoints.contains(expected) ? expected : "")
      let mp = fuseMp.isEmpty ? diskutilMp : fuseMp
      let fuse = !fuseMp.isEmpty
      out.append(
        NTFSVolume(
          id: ident,
          name: volumeName,
          size: size,
          mountPoint: mp,
          isWritableFuse: fuse,
          isReadOnlyMounted: !mp.isEmpty && !fuse
        )
      )
    }
    return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

private struct MountTable {
  var fusePoints: Set<String>
}

private func currentMounts() -> MountTable {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/sbin/mount")
  proc.standardOutput = Pipe()
  proc.standardError = Pipe()
  try? proc.run()
  proc.waitUntilExit()
  let data = (proc.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  let text = String(data: data, encoding: .utf8) ?? ""
  var fuse = Set<String>()
  for line in text.split(separator: "\n") {
    let s = String(line)
    let lower = s.lowercased()
    guard lower.contains("macfuse")
      || lower.contains("osxfuse")
      || lower.contains("fuse-t")
      || lower.contains("fuset")
      || lower.contains("ntfs-3g")
      || s.contains(" fuse,")
    else { continue }
    if let range = s.range(of: " on "),
       let end = s.range(of: " (") {
      fuse.insert(String(s[range.upperBound..<end.lowerBound]))
    }
  }
  return MountTable(fusePoints: fuse)
}

private func diskutilPlist(_ args: [String]) -> [String: Any]? {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
  proc.arguments = args
  let out = Pipe()
  proc.standardOutput = out
  proc.standardError = Pipe()
  do {
    try proc.run()
    proc.waitUntilExit()
  } catch {
    return nil
  }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
}

enum Privileged {
  static let helperCandidates = [
    "/usr/local/sbin/ntfs-rw-helper",
    Bundle.main.path(forResource: "ntfs-rw-helper", ofType: nil),
  ].compactMap { $0 }

  static var helperPath: String? {
    helperCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  struct Outcome {
    let ok: Bool
    let text: String
  }

  static func run(_ cmd: String, _ deviceId: String) -> Outcome {
    guard let helper = helperPath else {
      return Outcome(ok: false, text: "未找到挂载助手。请先运行 ./install.sh")
    }
    let sudo = Process()
    sudo.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    sudo.arguments = ["-n", helper, cmd, deviceId]
    let sudoOut = Pipe()
    let sudoErr = Pipe()
    sudo.standardOutput = sudoOut
    sudo.standardError = sudoErr
    do {
      try sudo.run()
      sudo.waitUntilExit()
      let out = String(data: sudoOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let err = String(data: sudoErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if sudo.terminationStatus == 0 {
        return Outcome(ok: true, text: out.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      if !err.lowercased().contains("password") && sudo.terminationStatus != 1 {
        return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
      }
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }

    let osa = Process()
    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osa.arguments = ["-e", "do shell script \"\(helper) \(cmd) \(deviceId)\" with administrator privileges"]
    let osaOut = Pipe()
    let osaErr = Pipe()
    osa.standardOutput = osaOut
    osa.standardError = osaErr
    do {
      try osa.run()
      osa.waitUntilExit()
      let out = String(data: osaOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let err = String(data: osaErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      if osa.terminationStatus == 0 {
        return Outcome(ok: true, text: out.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return Outcome(ok: false, text: (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      return Outcome(ok: false, text: error.localizedDescription)
    }
  }
}

struct MenuRoot: View {
  @ObservedObject var store: VolumeStore

  var body: some View {
    if store.volumes.isEmpty {
      Text("没有检测到 NTFS 硬盘")
      Text("插入 Windows 格式的移动盘后再点菜单")
        .foregroundStyle(.secondary)
    } else {
      ForEach(store.volumes) { vol in
        Menu {
          Button("以可写方式挂载") { store.mount(vol) }
            .disabled(vol.isWritableFuse || store.busyId != nil)
          Button("在访达中打开") {
            NSWorkspace.shared.open(URL(fileURLWithPath: vol.expectedMountPoint))
          }
          .disabled(vol.mountPoint.isEmpty)
          Divider()
          Button("卸载") { store.unmount(vol) }
            .disabled(vol.mountPoint.isEmpty || store.busyId != nil)
          Button("推出（可安全拔出）") { store.eject(vol) }
            .disabled(store.busyId != nil)
        } label: {
          Text("\(statusDot(vol)) \(vol.name)  ·  \(vol.stateLabel)  ·  \(vol.sizeLabel)")
        }
      }
      Divider()
      Button("全部以可写方式挂载") { store.mountAll() }
        .keyboardShortcut("m")
        .disabled(store.volumes.allSatisfy(\.isWritableFuse) || store.busyId != nil)
    }
    Divider()
    Button("刷新") { store.refresh() }
      .keyboardShortcut("r")
    Button(store.launchAtLogin ? "开机启动：开" : "开机启动：关") {
      store.toggleLogin()
    }
    if !store.message.isEmpty {
      Text(store.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }
    Divider()
    Button("退出 NTFS 读写") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }

  private func statusDot(_ vol: NTFSVolume) -> String {
    if store.busyId == vol.id { return "…" }
    if vol.isWritableFuse { return "●" }
    if vol.isReadOnlyMounted { return "○" }
    return "◌"
  }
}
