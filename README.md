# NTFS 读写 · NTFSMount

[下载安装包](https://github.com/bio-apple/NTFSMount/releases) · [English](#english)

给 Mac 外置 NTFS 盘可写访问，不用内核扩展。

![主窗口](docs/screenshots/window.png)

![菜单栏](docs/screenshots/menubar.png)

| | |
| --- | --- |
| 系统 | 仅 Apple Silicon（M 芯片）+ macOS 13.0+，**不支持 Intel Mac（x86_64）** |
| 应用名 | **NTFS 读写**（菜单栏 **NTFS**，聚焦也可搜 **NTFSMount**） |
| 安装包 | `NTFSMount.app`，拖到「应用程序」 |
| 分发 | 直发，不上 Mac App Store |

当前 Release 是**个人使用、未公证**预发布（GitHub 的 Latest 不会指向预发布，请从 [Releases](https://github.com/bio-apple/NTFSMount/releases) 选带 `NTFSMount.dmg` 的 tag）。Gatekeeper 会拦截时：按住 Control 点应用 → **打开**；也可在「系统设置 → 隐私与安全性」点「仍要打开」。不要镜像本 DMG。许可证拆分见 [NOTICE](./NOTICE)。

**`go-nfsv4` 不是 GPL，默认仅供个人使用。作为产品分发或销售前，必须取得 [FUSE-T](https://www.fuse-t.org/) 的书面许可。** 见 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) 与 [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)。

---

**插入 → 可写 → 推出（可安全拔出） → 再拔线。**

写 NTFS 可能损坏数据，请先备份。第一次启动会确认条款；第一次可写挂载会再确认一次。

## 快速开始

仅 Apple Silicon（M 芯片）与 macOS 13.0+，**不支持 Intel Mac（x86_64）**。

1. 下载 DMG
2. 拖入「应用程序」
3. 打开并同意条款（回车是「退出」；同意后在窗口点「安装…」。未公证包要管理员密码，已公证包优先系统服务授权）
4. 插入外置 NTFS
5. 开始使用

## 安装

1. 从 [Releases](https://github.com/bio-apple/NTFSMount/releases) 下载 `NTFSMount.dmg`（当前为 pre-release，不是 GitHub Latest）。
2. 对照 Release 页上的 SHA256，在终端校验完整性：

   ```bash
   shasum -a 256 NTFSMount.dmg
   ```

   结果应与 Release 正文完全一致。也可同时下载 `NTFSMount.dmg.sha256`，执行 `shasum -a 256 -c NTFSMount.dmg.sha256`。
3. 若提示无法验证开发者：**按住 Control 点应用 → 打开**（未公证包的第一步）；也可在「系统设置 → 隐私与安全性」点「仍要打开」。
4. 把 **NTFSMount** 拖到「应用程序」，打开。菜单栏出现 **NTFS**，第一次会弹出窗口。
5. 同意备份与个人使用条款（默认按钮是「退出」）。在窗口横幅或左侧 **设置** 点「安装…」。**未公证包会请求管理员密码**；已公证包优先用系统服务授权，失败再要密码。
6. 之后插入**外置** NTFS 盘会默认以可写方式挂载。内置盘 / Boot Camp 不会自动挂。

升级后若提示 **更新挂载助手**，先更新再格式化。

从源码打包：`./scripts/package-dmg.sh` → `dist/NTFSMount.dmg`，并写出 `dist/NTFSMount.dmg.sha256`。

## 日常使用

默认在菜单栏，不进程序坞。要程序坞或登录时打开：窗口 **设置**。

1. 插入 NTFS 硬盘（助手装好后外置盘会自动变成可写）。
2. 菜单栏 **NTFS** → 点盘名打开**子菜单** → **以可写方式挂载** / **卸载** / **推出（可安全拔出）**。
3. 或点 **打开窗口**：左侧选盘，右侧操作（类似磁盘工具）。
4. 访达里打开 `/Volumes/<卷名>`，照常拷贝、删除、重命名。
5. 用完：**推出（可安全拔出）** → 等盘从访达消失 → 再拔线。

不要不推出就拔线。Windows 没正常关机（休眠 / 快速启动）或卷不干净时，会**只读**挂载并通知你。

| 状态 | 含义 |
| --- | --- |
| 可写 | 已可读写，用访达即可 |
| 只读 · 系统 NTFS | 苹果自带只读驱动，可在子菜单改成可写（卷须干净） |
| 只读 · 休眠/未正常关机 | Windows 休眠或卷 dirty，请先在 Windows 彻底关机 |
| 未挂载 | 已检测到，在子菜单里挂上 |
| 处理中 | 正在操作 |

状态为「只读 · 系统 NTFS」时，可在子菜单里点「以可写方式挂载」手动改为可写，但卷必须是干净的（非 dirty / 非 Windows 休眠）。「只读 · 休眠/未正常关机」不要强行可写。

自动挂载、助手、日志都在窗口 **设置**，不在菜单栏。

## 格式化为 NTFS

只对外置**整盘**。点 **格式化为 NTFS…**，对话框会显示容量、设备号和序列号。输入**当前卷名**后还有一次确认。回车默认是 **取消**。内置盘会被拒绝。

## 卸载

窗口 **设置** → **卸载助手** 只去掉特权组件。完全删除应用：

```bash
./uninstall.sh
```

会退出应用，并删除 `/Applications/NTFSMount.app`、特权守护进程、残留 sudo 规则和自动挂载。不会推出已插入的硬盘。

## 开发

构建机需要：`brew install ntfs-3g`，以及一次 FUSE-T（只为提取 `go-nfsv4` 和 `libfuse.2.dylib`）。打包后的用户不必再装 FUSE-T。

应用是 Swift Package：`Sources/NTFSMountCore` 可单测，`Sources/NTFSMount` 是菜单栏应用（`VolumeStore` / `Privileged` / `UI/` / `Helpers/`）。`scripts/build.sh` 用 `swift build` 再打进 `.app`。真盘步骤见 [docs/MANUAL_TEST.md](./docs/MANUAL_TEST.md)。

```bash
./scripts/prepare-runtime.sh
swift test                    # NTFSVolume.scan mock、脏卷、格式化确认
./scripts/test-helper.sh      # 助手 selftest + swift test（无真盘、不装特权助手）
./scripts/build.sh
./scripts/package-dmg.sh    # 个人使用 DMG（默认）
```

`./scripts/test-helper.sh` 覆盖：

- 助手 `selftest` / `version`：磁盘 id 合法格式，拒绝 `;whoami`、空格、路径穿越、命令替换
- 以 `mount` 传入恶意 id 时助手拒绝（不真正挂载）
- 编译 `ntfsmount-helperd.c` 为 arm64
- README 文案回归（禁止已废弃的「无 Dock / 点盘名挂载」描述）
- `swift test`：mock 扫描 NTFS / ExFAT / 内置盘、脏卷与休眠只读、只读原因文案、格式化卷名确认、首次确认默认「退出」、`UserFacingError` 映射

不覆盖：真实 USB、live 挂载/卸载/格式化、sudo 安装/卸载助手、LaunchDaemon / sudoers。

对外公证发布需要 **Developer ID Application** 证书和 `notarytool`；只有取得 FUSE-T 书面许可后才可设 `FUSE_T_REDISTRIBUTION_OK=1`。否则保持未签名 / 个人使用。流程见 [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md) 和 [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md)。

特权助手优先用 `SMAppService` 注册签名钉扎的 LaunchDaemon（**已公证包**）；**未公证 / ad-hoc 通常失败**，再提示管理员密码。安装脚本只删除旧 `/etc/sudoers.d/ntfs-rw`，不会写入 NOPASSWD。`ntfs-rw-helper` 是仓库内 bash 源码，构建时签名并写入 SHA-256。

CI：`ShellCheck`、`Helper Build`、`Swift Build`；打 `v*` tag 且 `runtime/` 齐全时自动生成预发布 DMG。GitHub Latest 不会指向预发布。

## 许可

合并作品（含本仓库 Swift 与 ntfs-3g）为 **GPL-2.0-or-later**。见 [LICENSE](./LICENSE)、[NOTICE](./NOTICE) 与 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。

**`go-nfsv4` 不是 GPL，默认仅供个人使用。作为产品分发或销售前，必须取得 [FUSE-T](https://www.fuse-t.org/) 的书面许可。** 见 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) 与 [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)。

## English

<details>
<summary>English</summary>

[Download DMG](https://github.com/bio-apple/NTFSMount/releases)

Read and write Windows NTFS disks on Mac. No kernel extension.

![Main window](docs/screenshots/window.png)

![Menu bar](docs/screenshots/menubar.png)

| | |
| --- | --- |
| OS | Apple Silicon (M-series) + macOS 13.0+ only; **Intel Mac (x86_64) is not supported** |
| App name | **NTFS 读写** (menu bar **NTFS**; Spotlight also finds **NTFSMount**) |
| Package | `NTFSMount.app`, drag to Applications |
| Distribution | Direct download, not on the Mac App Store |

The current Release is a **personal-use, not notarized** pre-release (GitHub Latest does not point at pre-releases; pick a tag with `NTFSMount.dmg` from [Releases](https://github.com/bio-apple/NTFSMount/releases)). If macOS blocks it: Control-click the app → **Open**, or System Settings → Privacy & Security → **Open Anyway**. Do not mirror this DMG. License split: [NOTICE](./NOTICE).

**`go-nfsv4` is not GPL; personal use only by default. You must obtain a written FUSE-T license before distributing or selling this as a product.** See [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).

**Plug in → writable → 推出（可安全拔出） → unplug.**

Writing NTFS can corrupt data. Back up first. The app asks twice: at first launch, and at the first writable mount.

### Quick start

Apple Silicon (M-series) and macOS 13.0+ only; **Intel Mac (x86_64) is not supported**.

1. Download the DMG
2. Drag into Applications
3. Open and accept the terms (Return is **退出**; then click **安装…** in the window. Unnotarized builds ask for an admin password; notarized builds prefer the system service prompt)
4. Plug in an external NTFS disk
5. Start using it

### Install

1. Download `NTFSMount.dmg` from [Releases](https://github.com/bio-apple/NTFSMount/releases) (pre-release, not GitHub Latest).
2. Verify the download against the SHA256 on the Release page:

   ```bash
   shasum -a 256 NTFSMount.dmg
   ```

   The digest must match the Release notes exactly. You can also download `NTFSMount.dmg.sha256` and run `shasum -a 256 -c NTFSMount.dmg.sha256`.
3. If macOS says it cannot be opened: **Control-click → Open**, or **System Settings → Privacy & Security → Open Anyway**.
4. Drag **NTFSMount** to Applications and open it. The menu bar shows **NTFS**; a window opens on first launch.
5. Accept the notices (**退出** is the default). Install the helper from the banner or **设置**. **Unnotarized builds use an admin-password LaunchDaemon**; notarized builds try `SMAppService` first.
6. External NTFS disks then remount writable on insert. Internal / Boot Camp disks are never auto-mounted.

After an update, accept **更新挂载助手** before formatting.

From source: `./scripts/package-dmg.sh` → `dist/NTFSMount.dmg`, and `dist/NTFSMount.dmg.sha256`.

### Daily use

Menu bar only by default. Dock icon and login item are in window **设置**.

1. Plug in an NTFS drive. After the helper is installed, external disks remount writable.
2. Menu bar **NTFS** → disk **submenu** → **以可写方式挂载** / **卸载** / **推出（可安全拔出）**.
3. Or **打开窗口**: list on the left, actions on the right.
4. Finder opens `/Volumes/<name>`. Copy and edit as usual.
5. When done: **推出（可安全拔出）** → wait until it disappears → unplug.

Do not unplug without ejecting. Dirty volumes or Windows hibernation mount **read-only** and notify you.

| Status | Meaning |
| --- | --- |
| 可写 | Mounted read-write; use Finder |
| 只读 · 系统 NTFS | Apple’s read-only NTFS; remount writable from the submenu if the volume is clean |
| 只读 · 休眠/未正常关机 | Windows hibernation / dirty volume — shut down Windows fully first |
| 未挂载 | Detected; mount from the submenu |
| 处理中 | Operation in progress |

If status is **只读 · 系统 NTFS**, use **以可写方式挂载** in the submenu — only if the volume is clean (not dirty / not Windows hibernated). Do not force writable on **只读 · 休眠/未正常关机**.

Auto-mount, helper, and logs are in **设置**, not the menu bar.

### Format

External whole disk only. The dialog shows size, device id, and serial. Type the **current volume name**, then confirm again. Return defaults to **取消**. Internal disks are refused.

### Uninstall

Window **设置** → **卸载助手** removes the privileged helper only. To delete the app:

```bash
./uninstall.sh
```

Quits the app and removes the app bundle, helper daemon, leftover sudoers, and auto-mount. Does not eject a drive.

### Develop

The build machine needs `brew install ntfs-3g` and a one-time FUSE-T install (only to extract `go-nfsv4` and `libfuse.2.dylib`). Packaged-app users do not install FUSE-T.

The app is a Swift package: `Sources/NTFSMountCore` is unit-tested; `Sources/NTFSMount` is the menu-bar app (`VolumeStore` / `Privileged` / `UI/` / `Helpers/`). `scripts/build.sh` runs `swift build` then packs the `.app`.

```bash
./scripts/prepare-runtime.sh
swift test                    # NTFSVolume.scan mock, dirty volume, format confirm
./scripts/test-helper.sh      # helper selftest + swift test (no real disk, no helper install)
./scripts/build.sh
./scripts/package-dmg.sh    # personal-use DMG (default)
```

`./scripts/test-helper.sh` covers helper `selftest` / `version`, rejection of malicious disk ids, arm64 `ntfsmount-helperd.c`, README wording guards, and `swift test`. It does **not** insert USB, mount/unmount/format a real disk, or install the privileged helper.

Notarized public shipping needs a Developer ID Application identity and `notarytool`. Set `FUSE_T_REDISTRIBUTION_OK=1` only after written FUSE-T permission; otherwise keep unsigned / personal-use builds. See [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md) and [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md).

The helper prefers `SMAppService` (signature-pinned LaunchDaemon) on **notarized** builds. **Ad-hoc / unnotarized builds usually cannot register the system service** and fall back to an admin password. Install scripts never write sudoers NOPASSWD; they only remove leftovers. `ntfs-rw-helper` is in-repo bash, signed and SHA-256 checked at build.

CI runs ShellCheck, helper compile, and Swift build. Tags `v*` package a pre-release DMG when `runtime/` is in the checkout. GitHub Latest is not used for pre-releases.

### License

The combined work (this repo’s Swift and ntfs-3g) is **GPL-2.0-or-later**. See [LICENSE](./LICENSE), [NOTICE](./NOTICE), and [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).

**`go-nfsv4` is not GPL; personal use only by default. Written FUSE-T permission is required before product distribution or sale.** See [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).

</details>
