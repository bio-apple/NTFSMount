# NTFS 读写 · NTFSMount

[English](./README.md) · **简体中文**

给 Apple Silicon Mac 上的**外置 NTFS** 可写访问。**无 kext、不用关 SIP。** 仅 macOS 13+；不支持 Intel。

`Apple Silicon` · `macOS 13+` · `NTFS 可写` · `无 kext` · `个人使用预发布`

界面跟随系统语言（English / 简体中文 / 繁體中文 / 日本語）。

**[下载 NTFSMount v1.2.1（DMG）](https://github.com/bio-apple/NTFSMount/releases/download/v1.2.1/NTFSMount.dmg)** · [Releases 与 SHA256](https://github.com/bio-apple/NTFSMount/releases/tag/v1.2.1) — 用这一页，不要用 GitHub **Latest**，不要第三方镜像。

- **先备份。** 可写挂载或格式化可能损坏数据。在适用法律允许的范围内，作者不对数据损失负责。
- **未公证（ad-hoc）。** 系统可能拦截，需 Control-click → 打开（见快速开始）。
- **个人使用。** 捆绑的 FUSE-T `go-nfsv4` **不是 GPL**。上架、销售或镜像前须取得 [FUSE-T](https://www.fuse-t.org/) **书面许可并完成** Developer ID 公证。Swift / ntfs-3g 源码为 GPL-2.0-or-later，见 [NOTICE](./NOTICE)。

## 快速开始

1. 从 v1.2.1 GitHub pre-release 下载 **[NTFSMount.dmg](https://github.com/bio-apple/NTFSMount/releases/download/v1.2.1/NTFSMount.dmg)**。
2. 把 **NTFSMount** 拖入「应用程序」。本包未公证：**Control-click → 打开**，或「系统设置 → 隐私与安全性 → 仍要打开」。
3. 首次启动：回车 = **同意并继续**，再点 **安装…**（本 ad-hoc 包会要管理员密码）。
4. 可选（在本仓库克隆里）：`./scripts/ntfsmount diagnose`
5. 插入外置 NTFS。菜单栏 **NTFS** → 对应卷 → **以可写方式挂载**。

日常用菜单栏，不要把 CLI 当主路径。`ntfsmount mount diskNsM` 需要 root 与已装助手，见 [常见问题](#常见问题)。

## 功能

- 给**外置** NTFS 可写访问（用户态 FUSE-T，**无 kext**）
- 悬停菜单栏 **NTFS** 图标即可看到卷名、`NTFS • 可写/只读`、设备号和用量
- **推出（可安全拔出）** 会先释放 FUSE，等卷消失再拔线
- 抹掉外置**整盘**为 NTFS 在**根菜单**（不在单卷子菜单）；回车默认 **取消**
- 四种界面语言：English、简体中文、繁體中文、日本語

## 截图

**菜单栏**

![菜单栏](docs/screenshots/menubar.png)

**已挂载窗口**

![已挂载窗口](docs/screenshots/window.png)

## 系统要求

- **Apple Silicon** Mac（不支持 Intel；脚本会立刻退出）
- **macOS 13.0** 或更高
- **外置** NTFS 磁盘

## 安装

1. 下载 v1.2.1 DMG，用 `shasum -a 256 NTFSMount.dmg` 对照 [发布说明](https://github.com/bio-apple/NTFSMount/releases/tag/v1.2.1)。
2. 拖入「应用程序」，按 [快速开始](#快速开始) 打开。
3. 按提示安装挂载助手。之后可在 **设置** 卸载助手。完全卸载：`./uninstall.sh`（不删你自己装的 FUSE-T / MacFUSE）。

本项目没有 Homebrew tap / cask，不能 `brew tap bio-apple/ntfsmount`。NOTICE 禁止第三方镜像捆绑的 `go-nfsv4`。

## 使用

关窗不会退出；从程序坞或菜单退出才会。

```text
菜单栏「NTFS」
├ 打开窗口
├ 状态 · 盘名 · 容量     ← 悬停图标有四行卡片
│   ├ 以可写方式挂载 / 在访达中打开
│   └ 卸载 / 推出（可安全拔出）
├ 全部以可写方式挂载
├ 抹掉整盘为 NTFS…       ← 根菜单，不在单卷子菜单；回车默认取消
├ 刷新 / 诊断环境… / 设置… / 检查更新…
└ 退出 NTFS 读写
```

格式化只对外置**整盘**：输入当前卷名，回车默认 **取消**。

| 状态 | 做什么 |
| --- | --- |
| 可写 | 直接用 |
| 只读 · 系统 NTFS | 卷干净时，子菜单改成可写 |
| 只读 · 休眠/未正常关机 | 先在 Windows 彻底关机，不要强行可写 |

## 常见问题

**打不开？** 见 [快速开始](#快速开始)（Control-click → 打开）。仍不行：

```bash
xattr -d com.apple.quarantine /Applications/NTFSMount.app
open /Applications/NTFSMount.app
```

**菜单栏没有 NTFS？** 仅 Apple Silicon + macOS 13+。

**安装环境不对？** 菜单「诊断环境…」（不挂载、不装助手），或 `./scripts/ntfsmount diagnose`。不需要 macFUSE。

**一直要管理员密码？** 未公证包的预期行为。公证后才优先系统服务。

**盘是只读？** 系统 NTFS 可在卷干净时改可写。脏卷：「尝试修复脏卷…」（可能丢失未写入的 Windows 缓存；默认取消）。休眠/快速启动：彻底关机后再试；本应用不会静默删除 `hiberfil.sys`。

**没有 Latest？** 故意的。用 Releases 里的 pre-release DMG。

**怎么更新？** 菜单「检查更新…」会访问 GitHub（美国）。设置里自动检查**默认关**。信任来自 Sparkle EdDSA，不是 Developer ID。见 [docs/SPARKLE.md](./docs/SPARKLE.md)。

**要关 SIP 或装 macFUSE 吗？** 不要。本应用用 **FUSE-T**（用户态）+ ntfs-3g。开发机：`./scripts/check-fuse-deps.sh`。不要 `brew install macfuse` 或 `brew install fuse-t`。

**命令行挂载？** 仅给进阶用户，且助手已装好：

```bash
./scripts/ntfsmount list
sudo ./scripts/ntfsmount mount diskNsM
```

`mount` / `unmount` 需要 **root** 与已装助手。日常请用菜单栏。

**提交 Bug？** `./scripts/ntfsmount diagnose` 或 `--json`。卷 JSON：`list --json` / `status diskNsM --json`。

更多：[docs/MANUAL_TEST.md](./docs/MANUAL_TEST.md)。

## 架构

访达经 FUSE-T 的用户态 NFS 服务（`go-nfsv4`）再经 ntfs-3g 访问磁盘。菜单栏 App 保持普通用户权限；挂载 / 卸载 / 格式化经 Unix socket 交给 LaunchDaemon。

![架构](docs/screenshots/architecture.svg)

| 组件 | 做什么 |
| --- | --- |
| App | 列卷、确认格式化、设置 |
| `ntfsmount-helperd` | 用调用方 **CDHash + bundle id + 路径** 钉扎 |
| `ntfs-rw-helper` | 仓库内 bash；跑 `ntfs-3g` / `mkntfs`（`HELPER_VERSION=9`） |
| ntfs-3g + FUSE-T | 用户态读写，**不用 kext**。`go-nfsv4` 是 FUSE-T 的 NFS 服务，不是通用 libkrun 微虚拟机产品名 |

Helper IPC 为长度前缀 **v2**（可回退 v1）。format/fix 最长等待 10 分钟并带心跳。界面一次只跑一条特权命令；客户端已断开则不执行。不写 `sudoers`。

## 限制

- 全盘自动挂载**不是**卖点（[#1](https://github.com/bio-apple/NTFSMount/issues/1)）。插入磁盘后用「以可写方式挂载」。
- 不上 Mac App Store。
- 没有 Homebrew tap / cask（GPL + 捆绑 FUSE-T `go-nfsv4` + 未公证；[NOTICE](./NOTICE) 禁止镜像）。
- 捆绑的 `go-nfsv4` 默认仅个人使用。在取得 FUSE-T 书面许可 **并** 完成 Developer ID 公证之前，GitHub Release 保持 pre-release。

## 安全

- 不写 `sudoers`。提权靠一次性安装的 LaunchDaemon。
- 助手用存储的 **CDHash**、bundle id 和路径认证调用方。
- 特权操作由 App 串行（`busyId`）；已断开的客户端不会被执行。
- 格式化与脏卷修复对话框默认 **取消**（回车不会确认）。
- 从不静默删除 `hiberfil.sys`。
- Sparkle 自动检查**默认关**；检查会访问 **GitHub（美国）**，不是作者自建服务器。见 [docs/SPARKLE.md](./docs/SPARKLE.md) 与 [NOTICE](./NOTICE)。

## 开发

```bash
./scripts/check-fuse-deps.sh
./scripts/ci-shellcheck.sh
./scripts/prepare-runtime.sh
swift test && ./scripts/test-helper.sh
./scripts/coverage.sh
./scripts/ntfsmount diagnose --json
./scripts/build.sh && ./scripts/package-dmg.sh
```

构建机：Homebrew `ntfs-3g` + **FUSE-T 1.2.7** 官方 pkg。钉死版本：[runtime/versions.txt](./runtime/versions.txt)。Intel 构建会被拒绝。

CI：SwiftLint、ShellCheck、helper selftest、`swift test`、安全 grep、arm64 构建。真盘可选：`.github/workflows/manual-disk-test.yml`。

推送 `v*` tag 会打 DMG Release。没有 Developer ID 凭据时仍是未公证 **pre-release**。不要把 Latest 指到未授权包。

## 许可

本仓库 Swift 与 ntfs-3g 为 GPL-2.0-or-later（[LICENSE](./LICENSE)）。`go-nfsv4` **不在**该 GPL 授权范围内。拆分与再分发规则：[NOTICE](./NOTICE)、[docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)。
