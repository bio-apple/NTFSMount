# NTFS 读写 · NTFSMount

[下载](https://github.com/bio-apple/NTFSMount/releases) · [English](#english)

给 Mac **外置 NTFS 盘可写访问**，不用内核扩展。直发，不上 Mac App Store。

仅 **Apple Silicon（M 芯片）+ macOS 13.0+**。**不支持 Intel Mac。** 菜单栏显示 **NTFS**，聚焦也可搜 **NTFSMount**。

当前包是**个人使用、未公证**预发布。GitHub Latest **不会**指向预发布，请从 [Releases](https://github.com/bio-apple/NTFSMount/releases) 选带 `NTFSMount.dmg` 的 tag。**不要镜像。** 许可证拆分见 [NOTICE](./NOTICE)。

**`go-nfsv4` 不是 GPL，默认仅供个人使用。作为产品分发或销售前，必须取得 [FUSE-T](https://www.fuse-t.org/) 的书面许可。**

写 NTFS 可能损坏数据，请先备份。

**插入 → 可写 → 推出（可安全拔出） → 再拔线。**

## 快速开始

1. 从 Releases 下载 `NTFSMount.dmg`，用下面命令核对 SHA256。
2. 拖入「应用程序」。若系统拦截：按住 Control 点应用 → **打开**，或「系统设置 → 隐私与安全性」→ **仍要打开**。
3. 打开应用。确认框里回车是 **退出**，须点 **同意并继续**。
4. 在窗口点 **安装…**（未公证要管理员密码；已公证优先系统服务授权）。
5. 插入外置 NTFS，用访达读写。用完先 **推出（可安全拔出）**，等盘消失再拔线。

```bash
shasum -a 256 NTFSMount.dmg
```

结果须与 Release 正文一致。也可：`shasum -a 256 -c NTFSMount.dmg.sha256`。

![主窗口](docs/screenshots/window.png)

![菜单栏](docs/screenshots/menubar.png)

内置盘 / Boot Camp 不会自动挂。升级后若提示 **更新挂载助手**，先更新再格式化。

## 日常使用

默认只在菜单栏。程序坞、登录时打开、自动挂载、助手和日志都在窗口 **设置**。

菜单栏 **NTFS** → 点盘名打开子菜单 → **以可写方式挂载** / **卸载** / **推出（可安全拔出）**。或 **打开窗口**，左侧选盘、右侧操作。

| 状态 | 含义 |
| --- | --- |
| 可写 | 已可读写 |
| 只读 · 系统 NTFS | 苹果自带只读驱动。卷干净时可在子菜单改成可写 |
| 只读 · 休眠/未正常关机 | Windows 休眠或卷 dirty。先在 Windows 彻底关机，不要强行可写 |
| 未挂载 | 已检测到，在子菜单里挂上 |
| 处理中 | 正在操作 |

## 格式化为 NTFS

只对外置**整盘**。对话框会显示容量、设备号和序列号。输入**当前卷名**后再确认一次。回车默认 **取消**。内置盘会被拒绝。

## 卸载

**设置 → 卸载助手** 只去掉特权组件。完全删除：

```bash
./uninstall.sh
```

会退出应用，并删除 `/Applications/NTFSMount.app`、守护进程和残留 sudo 规则。不会推出已插入的硬盘。核对：`bash scripts/check-helper-gone.sh`。

## 开发

构建机需要 `brew install ntfs-3g`，以及一次 FUSE-T（只为提取 `go-nfsv4` 和 `libfuse.2.dylib`）。用户不必再装 FUSE-T。

Swift Package：`NTFSMountCore` 可单测，`NTFSMount` 是菜单栏应用。真盘步骤见 [docs/MANUAL_TEST.md](./docs/MANUAL_TEST.md)。

```bash
./scripts/prepare-runtime.sh
swift test
./scripts/test-helper.sh      # 无真盘、不装特权助手
./scripts/build.sh
./scripts/package-dmg.sh      # 个人使用 DMG；写出 .sha256
```

`test-helper.sh`：助手 `selftest` / 恶意 disk id 拒绝、helperd arm64 编译、mock 扫描 / 脏卷 / 格式化确认 / 首次确认默认退出。不覆盖真实 USB、live 挂载或 sudo 安装助手。

对外公证需要 **Developer ID Application** 和 `notarytool`。只有 FUSE-T 书面许可后才可设 `FUSE_T_REDISTRIBUTION_OK=1`。未公证包安装助手会要管理员密码；已公证包优先 `SMAppService`。详见 [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)、[docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md)。

## 许可

本仓库 Swift 与 ntfs-3g 为 **GPL-2.0-or-later**（[LICENSE](./LICENSE)）。**`go-nfsv4` 单独授权，不能按 GPL 再分发。** 见 [NOTICE](./NOTICE)、[THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。

## English

<details>
<summary>English</summary>

[Download](https://github.com/bio-apple/NTFSMount/releases)

Writable NTFS for **external** disks on Mac. No kernel extension. Direct download, not the Mac App Store.

**Apple Silicon + macOS 13.0+ only. Intel Macs are not supported.** Menu bar: **NTFS**. Spotlight also finds **NTFSMount**.

Current builds are **personal-use, not notarized** pre-releases. GitHub Latest does **not** point at them. Pick a tag with `NTFSMount.dmg`. Do not mirror. License split: [NOTICE](./NOTICE).

**`go-nfsv4` is not GPL. Written [FUSE-T](https://www.fuse-t.org/) permission is required before distributing or selling this as a product.** Writing NTFS can corrupt data. Back up first.

**Plug in → writable → Eject → unplug.**

### Quick start

1. Download `NTFSMount.dmg` and check SHA256 against the Release notes: `shasum -a 256 NTFSMount.dmg`
2. Drag to Applications. If blocked: Control-click → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
3. First dialog: Return is **退出** (Quit). Click **同意并继续** to continue. The UI is Simplified Chinese.
4. Click **安装…** in the window (admin password on unnotarized builds; system service on notarized builds).
5. Plug in an external NTFS disk. When done, **推出（可安全拔出）**, wait until it disappears, then unplug.

Internal / Boot Camp disks are never auto-mounted. After an update, accept **更新挂载助手** before formatting.

### Daily use

Menu bar **NTFS** → disk submenu. Dock, login item, auto-mount, helper, and logs are in window **设置**.

| Status | Meaning |
| --- | --- |
| 可写 | Read-write |
| 只读 · 系统 NTFS | Apple’s read-only NTFS; remount writable from the submenu if the volume is clean |
| 只读 · 休眠/未正常关机 | Hibernation / dirty — shut down Windows fully; do not force writable |
| 未挂载 | Detected; mount from the submenu |
| 处理中 | Busy |

Format is external whole disk only: type the current volume name, confirm again. Return defaults to **取消**. Uninstall helper in **设置**; `./uninstall.sh` removes the app.

### Develop

```bash
./scripts/prepare-runtime.sh
swift test
./scripts/test-helper.sh
./scripts/build.sh
./scripts/package-dmg.sh
```

`test-helper.sh` does not touch a real USB or install the privileged helper. Notarized shipping needs a Developer ID and `notarytool`. Set `FUSE_T_REDISTRIBUTION_OK=1` only after written FUSE-T permission. See [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).

This repo’s Swift and ntfs-3g are **GPL-2.0-or-later**. `go-nfsv4` is not. See [NOTICE](./NOTICE).

</details>
