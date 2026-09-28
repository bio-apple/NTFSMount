# NTFS 读写 · NTFSMount

[English](./README.md) · **简体中文**

给 Apple Silicon Mac 上的**外置 NTFS** 可写访问（macOS 13+）。无内核扩展、不用关 SIP。不支持 Intel。界面跟随系统语言（English / 简体中文 / 繁體中文 / 日本語）。

**[下载 v1.2.1 DMG](https://github.com/bio-apple/NTFSMount/releases/download/v1.2.1/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/tag/v1.2.1)

- **先备份。** 可写挂载或格式化可能损坏数据。
- **未公证。** 按住 Control 点应用 → **打开**，或「系统设置 → 隐私与安全性 → **仍要打开**」。
- **个人使用。** 捆绑的 FUSE-T `go-nfsv4` 不是 GPL。上架或销售前须取得 [FUSE-T](https://www.fuse-t.org/) **书面许可并完成** Developer ID 公证。见 [NOTICE](./NOTICE)。

## 快速开始

1. 下载上面的 DMG（用这一页的 pre-release，不要用 GitHub Latest）。
2. 把 NTFSMount 拖进「应用程序」，按上面的方式打开。
3. 同意后点 **安装…** 挂载助手（本包会要管理员密码）。之后可在 **设置** 卸助手；完全卸载：`./uninstall.sh`。
4. 插入外置 NTFS → 菜单栏 **NTFS** → **以可写方式挂载**。

关掉窗口不会退出；从菜单或程序坞退出才会。

## 截图

<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/menubar.png" alt="菜单栏"><br>菜单栏</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/window.png" alt="窗口"><br>窗口</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/settings.png" alt="设置"><br>设置</td>
</tr>
</table>

## 使用

| 状态 | 做什么 |
| --- | --- |
| 可写 | 直接用 |
| 只读 · 系统 NTFS | 卷干净时，子菜单改成可写 |
| 只读 · 休眠/未正常关机 | 先在 Windows 彻底关机，不要强行可写 |

抹成 NTFS 只对外置**整盘**，在根菜单。回车默认 **取消**。本应用不会静默删除 `hiberfil.sys`。

## 常见问题

**打不开？** Control-click → 打开。仍不行：

```bash
xattr -d com.apple.quarantine /Applications/NTFSMount.app
```

**一直要管理员密码？** 未公证包的预期行为。

**安装看起来不对？** 菜单「诊断环境…」（只读；不挂载、不装助手）。

## 架构

访达经用户态 FUSE-T（`go-nfsv4`）和 ntfs-3g 访问磁盘。应用保持普通权限；挂载 / 卸载 / 格式化经 Unix socket 交给 LaunchDaemon。不写 `sudoers`。

![架构](docs/screenshots/architecture.svg)

## 开发

```bash
./scripts/check-fuse-deps.sh
swift test && ./scripts/test-helper.sh
./scripts/build.sh && ./scripts/package-dmg.sh
```

## 许可

本仓库 Swift 与 ntfs-3g 为 GPL-2.0-or-later（[LICENSE](./LICENSE)）。`go-nfsv4` 不在该授权范围内。再分发：[NOTICE](./NOTICE)、[docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)。
