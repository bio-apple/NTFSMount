import AppKit
import NTFSMountCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: VolumeStore
  @State private var logText = AppLog.tail()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("设置")
          .font(.title2.weight(.semibold))

        GroupBox("挂载") {
          VStack(alignment: .leading, spacing: 10) {
            Toggle("插入时自动挂载外置 NTFS", isOn: Binding(
              get: { store.autoMount },
              set: { _ in store.toggleAutoMount() }
            ))
            .disabled(store.busyId != nil || !store.helperInstalled || Privileged.helperNeedsUpdate)
            Text("内置盘与 Boot Camp 不会自动挂载。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
        }

        GroupBox("外观与启动") {
          VStack(alignment: .leading, spacing: 10) {
            Toggle("登录时打开", isOn: Binding(
              get: { store.launchAtLogin },
              set: { _ in store.toggleLogin() }
            ))
            Toggle("在程序坞显示", isOn: Binding(
              get: { store.showDock },
              set: { _ in store.toggleDock() }
            ))
          }
          .padding(8)
        }

        GroupBox("挂载助手") {
          VStack(alignment: .leading, spacing: 10) {
            Text(helperStatus)
              .font(.callout)
            HStack {
              if !store.helperInstalled {
                Button("安装…") { store.installHelper() }
              } else if Privileged.helperNeedsUpdate {
                Button("更新…") { store.installHelper() }
              }
              if store.helperInstalled {
                Button("卸载助手…", role: .destructive) { store.confirmUninstallHelper() }
              }
            }
            Text(helperInstallHint)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(8)
        }

        GroupBox("兼容性") {
          VStack(alignment: .leading, spacing: 8) {
            Text(MacOSCompat.noticeBody)
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(8)
        }

        GroupBox("日志") {
          VStack(alignment: .leading, spacing: 8) {
            ScrollView {
              Text(logText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140, maxHeight: 220)
            HStack {
              Button("刷新日志") { logText = AppLog.tail() }
              Button("在控制台打开") { LogViewer.open() }
            }
          }
          .padding(8)
        }

        GroupBox("关于与隐私") {
          VStack(alignment: .leading, spacing: 8) {
            Text("NTFS 读写（NTFSMount）· 直发，不上 Mac App Store。不联网。")
              .font(.callout)
            Text(SigningStatus.isNotarized
              ? "当前构建已公证。"
              : (SigningStatus.isDeveloperID
                ? "已用 Developer ID 签名，尚未公证。按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。"
                : "当前构建未公证（ad-hoc），Gatekeeper 可能拦截。按住 Control 点应用 → 打开；也可在「系统设置 → 隐私与安全性」点「仍要打开」。"))
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack {
              Button("关于与隐私…") { store.showAbout() }
            }
          }
          .padding(8)
        }

        if !store.message.isEmpty {
          Text(store.message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .padding(28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { logText = AppLog.tail() }
  }

  private var helperStatus: String {
    if !store.helperInstalled { return "尚未安装。第一次使用请点「安装…」。" }
    if Privileged.helperNeedsUpdate { return "需要更新后才能使用全部功能。" }
    if Privileged.hasLegacySudoers { return "仍有旧版 sudo 规则，请更新助手以换成签名钉扎。" }
    return "已安装。特权调用经守护进程校验本应用签名。"
  }

  private var helperInstallHint: String {
    if SigningStatus.isNotarized {
      return "已公证：优先用系统服务授权；失败再输入管理员密码。"
    }
    return "未公证包无法稳定使用系统服务，安装助手会请求管理员密码。"
  }
}
