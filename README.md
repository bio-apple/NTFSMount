# NTFS 读写 · NTFSMount

[Download DMG](https://github.com/bio-apple/NTFSMount/releases/latest) · [下载安装包](https://github.com/bio-apple/NTFSMount/releases/latest)

给 Mac 外置 NTFS 盘可写访问，不用内核扩展。  
Read and write Windows NTFS disks on Mac. No kernel extension.

| | |
| --- | --- |
| 系统 · OS | Apple Silicon（M 芯片），macOS 13.0+ |
| 应用名 | **NTFS 读写**（菜单栏 **NTFS**，聚焦也可搜 **NTFSMount**） |
| 安装包 | `NTFSMount.app`，拖到「应用程序」 |
| 分发 | 直发，不上 Mac App Store |

当前 Release 是**个人使用、未公证**预发布。Gatekeeper 会拦截时：按住 Control 点应用 → **打开**。  
The current Release is a **personal-use, not notarized** pre-release. If macOS blocks it: Control-click the app → **Open**.

---

**插入 → 可写 → 推出（可安全拔出） → 再拔线。**  
**Plug in → writable → 推出（可安全拔出） → unplug.**

写 NTFS 可能损坏数据，请先备份。第一次启动会确认条款；第一次可写挂载会再确认一次。  
Writing NTFS can corrupt data. Back up first. The app asks twice: at first launch, and at the first writable mount.

## 安装 · Install

1. 从 [Releases](https://github.com/bio-apple/NTFSMount/releases/latest) 下载 `NTFSMount.dmg`。  
   Download `NTFSMount.dmg` from [Releases](https://github.com/bio-apple/NTFSMount/releases/latest).
2. 若提示无法验证开发者：**按住 Control 点应用 → 打开**（未公证包的第一步）。  
   If macOS says it cannot be opened: **Control-click → Open**.
3. 把 **NTFSMount** 拖到「应用程序」，打开。菜单栏出现 **NTFS**，第一次会弹出窗口。  
   Drag **NTFSMount** to Applications and open it. The menu bar shows **NTFS**; a window opens on first launch.
4. 同意备份与个人使用条款。在窗口横幅或左侧 **设置** 点「安装…」，输入一次管理员密码。  
   Accept the notices. Install the helper from the banner or **设置** (one admin password).
5. 之后插入**外置** NTFS 盘会默认以可写方式挂载。内置盘 / Boot Camp 不会自动挂。  
   External NTFS disks then remount writable on insert. Internal / Boot Camp disks are never auto-mounted.

升级后若提示 **更新挂载助手**，先更新再格式化。  
After an update, accept **更新挂载助手** before formatting.

从源码打包：`./scripts/package-dmg.sh` → `dist/NTFSMount.dmg`。

## 日常使用 · Daily use

默认在菜单栏，不进程序坞。要程序坞或登录时打开：窗口 **设置**。  
Menu bar only by default. Dock icon and login item are in window **设置**.

1. 插入 NTFS 硬盘（助手装好后外置盘会自动变成可写）。  
   Plug in an NTFS drive. After the helper is installed, external disks remount writable.
2. 菜单栏 **NTFS** → 点盘名打开**子菜单** → **以可写方式挂载** / **卸载** / **推出（可安全拔出）**。  
   Menu bar **NTFS** → disk **submenu** → mount writable, unmount, or eject.
3. 或点 **打开窗口**：左侧选盘，右侧操作（类似磁盘工具）。  
   Or **打开窗口**: list on the left, actions on the right.
4. 访达里打开 `/Volumes/<卷名>`，照常拷贝、删除、重命名。  
   Finder opens `/Volumes/<name>`. Copy and edit as usual.
5. 用完：**推出（可安全拔出）** → 等盘从访达消失 → 再拔线。  
   When done: **推出（可安全拔出）** → wait until it disappears → unplug.

不要不推出就拔线。Windows 没正常关机（休眠 / 快速启动）或卷不干净时，会**只读**挂载并通知你。  
Do not unplug without ejecting. Dirty volumes or Windows hibernation mount **read-only** and notify you.

| 状态 | 含义 |
| --- | --- |
| 可写 | 已可读写，用访达即可 |
| 只读 | 系统只读，在子菜单里改成可写 |
| 未挂载 | 已检测到，在子菜单里挂上 |
| 处理中 | 正在操作 |

自动挂载、助手、日志都在窗口 **设置**，不在菜单栏。  
Auto-mount, helper, and logs are in **设置**, not the menu bar.

## 格式化为 NTFS · Format

只对外置**整盘**。点 **格式化为 NTFS…**，输入**当前卷名**确认。默认按钮是 **取消**。内置盘会被拒绝。  
External whole disk only. Type the **current volume name** to confirm. Default button is **取消**. Internal disks are refused.

## 卸载 · Uninstall

窗口 **设置** → **卸载助手** 只去掉特权组件。完全删除应用：

```bash
./uninstall.sh
```

会退出应用，并删除 `/Applications/NTFSMount.app`、特权守护进程、残留 sudo 规则和自动挂载。不会推出已插入的硬盘。  
Quits the app and removes the app bundle, helper daemon, leftover sudoers, and auto-mount. Does not eject a drive.

## 开发 · Develop

构建机需要：`brew install ntfs-3g`，以及一次 FUSE-T（只为提取 `go-nfsv4` 和 `libfuse.2.dylib`）。打包后的用户不必再装 FUSE-T。

```bash
./scripts/prepare-runtime.sh
./scripts/test-helper.sh
./scripts/build.sh
./scripts/package-dmg.sh    # 个人使用 DMG（默认）
```

公证与产品分发见 [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md) 和 [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md)。需要 Developer ID，以及 FUSE-T 对 `go-nfsv4` 的书面授权（`FUSE_T_REDISTRIBUTION_OK=1`）。  
Notarization and commercial shipping: [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md). Needs a Developer ID and a FUSE-T redistribution license.

新安装的特权助手是 LaunchDaemon（校验本应用签名），不再写 `/etc/sudoers.d` 免密。  
New installs use a signature-pinned LaunchDaemon, not sudoers NOPASSWD.

## 许可 · License

合并作品（含本仓库 Swift 与 ntfs-3g）为 **GPL-2.0-or-later**。见 [LICENSE](./LICENSE) 与 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。

`go-nfsv4` 不是 GPL，默认仅供**个人使用**。作为产品分发或销售前须向 [FUSE-T](https://www.fuse-t.org/) 取得许可。  
`go-nfsv4` is not GPL. Personal use only until you have a FUSE-T license.
