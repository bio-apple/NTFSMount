# NTFSMount · NTFS 读写

[Releases](https://github.com/bio-apple/NTFSMount/releases) · 有 DMG 再从这里下。没有资产时请从源码构建。

Read and write Windows (NTFS) drives on macOS. Menu bar: **NTFS**. Display name: **NTFS 读写**. Spotlight also finds **NTFSMount**. Package: `NTFSMount.app`. Direct distribution (not Mac App Store).  
在 macOS 上读写 Windows（NTFS）硬盘。菜单栏 **NTFS**，显示名 **NTFS 读写**，聚焦也可搜 **NTFSMount**。安装包 `NTFSMount.app`。Developer ID 直发，不上 Mac App Store。

**Apple Silicon (M series) and macOS 13.0+ only.**  
**当前仅支持 Apple Silicon（M 芯片）及 macOS 13.0+。**

macOS mounts NTFS read-only. This app bundles **ntfs-3g**, **mkntfs**, and a userspace FUSE stack inside `NTFSMount.app` — no kernel extension, no system FUSE-T at runtime.  
macOS 默认把 NTFS 挂成只读。本应用把 **ntfs-3g**、**mkntfs** 和用户态 FUSE 打进 `NTFSMount.app`：不用内核扩展，运行时也不依赖系统里的 FUSE-T。

This project is **GPL-2.0-or-later**. FUSE-T `go-nfsv4` is personal-use unless you have a commercial license. See [LICENSE](./LICENSE), [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md), and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).  
本项目为 **GPL-2.0-or-later**。FUSE-T 的 `go-nfsv4` 仅供个人使用，除非已取得商业许可。

**Plug in → writable by default → 推出（可安全拔出） → unplug.**  
**插入硬盘 → 默认以可写方式挂载 → 推出（可安全拔出） → 再拔线。**

## Disclaimer · 免责声明

**Using a third-party driver to change NTFS mount permissions can corrupt data. Back up anything important first.**  
**使用第三方驱动修改 NTFS 挂载权限存在数据损坏风险，请确保重要数据已提前备份。**

The first launch asks you to accept backup + personal-use terms. The first writable mount asks once more.  
第一次启动会确认备份与个人使用条款；第一次可写挂载会再确认一次。

## Install · 安装

1. Open `dist/NTFSMount.dmg` (build with `./scripts/package-dmg.sh`), or a GitHub Release asset when one exists.  
   打开 `dist/NTFSMount.dmg`，或 Releases 里已上传的包。
2. Drag **NTFSMount** to **Applications**.  
   把 **NTFSMount** 拖到「应用程序」。
3. Open it. The menu bar shows **NTFS**; a window opens on first launch.  
   打开应用，菜单栏出现 **NTFS**，第一次会打开窗口。
4. Accept the legal / backup notice. Install the helper from the window banner or **设置** (one admin password). That installs a signature-pinned LaunchDaemon — not a sudoers NOPASSWD rule. Auto-mount on insert is then enabled for **external** disks only.  
   同意条款后，在窗口横幅或 **设置** 安装挂载助手（一次管理员密码）。这会装带签名钉扎的特权守护进程，不再写 sudoers 免密。之后仅对外置盘默认打开「插入时自动挂载」。

A notarized build opens normally. If macOS says the app cannot be opened, the DMG was not notarized: Control-click → **Open**. That is step one on ad-hoc builds, not a footnote.  
已公证的包可直接打开。若提示无法打开，说明该 DMG 未公证：按住 Control 点应用 → 打开。未公证包应把这一步当作安装第一步。

After an update, the app may ask to **更新挂载助手** (one admin password). Do that before formatting.  
升级后可能提示 **更新挂载助手**。格式化前请先更新。

## Launch · 启动

Finder → **Applications** → **NTFSMount**, Spotlight `NTFS` / `NTFSMount`, or `open /Applications/NTFSMount.app`.  
访达 → **应用程序** → **NTFSMount**，聚焦搜 `NTFS` 或 `NTFSMount`，或 `open /Applications/NTFSMount.app`。

The app is a menu bar extra. **在程序坞显示** is off by default; turn it on in the window **设置**. Optional **登录时打开**.  
默认只在菜单栏。要程序坞图标：窗口 **设置** → **在程序坞显示**。**登录时打开** 同样在设置里，默认关。

## Mount and eject · 挂载与推出

1. Plug in an NTFS drive. With auto-mount on (default after helper install), external disks remount writable — after you have accepted the one-time writable warning.  
   插入 NTFS 硬盘。安装助手后默认自动挂载外置盘；需先完成那一次「已备份」确认。
2. Click **NTFS** in the menu bar. Open a disk’s **submenu** for **以可写方式挂载**, **卸载**, **推出**.  
   点菜单栏 **NTFS**。点某一块盘进入**子菜单**，再选 **以可写方式挂载** / **卸载** / **推出**。
3. Or use **打开窗口**: Disk Utility-style list on the left, mount/eject on the right.  
   或点 **打开窗口**：左侧磁盘列表，右侧挂载/推出（类似磁盘工具）。
4. Finder opens `/Volumes/<name>`. Copy, delete, rename as usual.  
   访达打开 `/Volumes/<卷名>`，可照常复制、删除、重命名。
5. When done: **推出（可安全拔出）** → wait until the disk disappears → unplug.  
   用完点 **推出（可安全拔出）** → 等盘从访达消失 → 再拔线。

Do not unplug without ejecting. Dirty volumes or Windows hibernation mount **read-only** and notify you.  
不要不推出就拔线。脏卷或 Windows 休眠会只读挂载并通知。

| Menu · 菜单 | Meaning · 含义 |
| --- | --- |
| **以可写方式挂载** | Remount writable / 在磁盘子菜单里以可写方式重新挂载 |
| **在访达中打开** | Open the mount in Finder |
| **卸载** | Unmount; cable stays in |
| **推出（可安全拔出）** | Unmount and mark safe to unplug |
| **设置…** | Window: auto-mount, login, Dock, helper, logs |
| **刷新** | Rescan disks |

| Status · 状态 | Meaning · 含义 |
| --- | --- |
| 可写 | Writable — use Finder |
| 只读 | macOS read-only — use the disk submenu to remount writable |
| 未挂载 | Detected, not mounted — same submenu |
| 处理中 | Busy |

Settings (auto-mount, login item, Dock, helper install/update/uninstall, log tail) live in the window, not the menu bar.  
自动挂载、登录时打开、程序坞、助手、日志在窗口 **设置**，不在菜单栏。

## Auto-mount on insert · 插入时自动挂载

Installing the helper turns **插入时自动挂载** on by default (`/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist`). Internal disks and disk images are skipped. Toggle it in **设置**.  
安装助手后默认打开。内置盘和磁盘映像会跳过。在 **设置** 里开关。

Privileged work goes through `com.bioapple.ntfsmount.helper` (Unix socket, caller CDHash pinned). There is no `/etc/sudoers.d` NOPASSWD rule on a new install.  
特权操作走守护进程和 Unix socket，按调用方 CDHash 钉扎。新安装不再写 sudoers 免密。

## Format as NTFS · 格式化为 NTFS

Erases an **external** whole disk. Type the **current volume name** to confirm. Default button is **取消**.  
抹掉一块**外置整盘**。必须输入**当前卷名**。默认按钮是 **取消**。

## Uninstall · 卸载

Window **设置** → **卸载助手**, or:

```bash
./uninstall.sh
```

Removes the app, helper daemon, socket, leftover sudoers, and auto-mount LaunchDaemon.  
删除应用、特权守护进程、socket、残留 sudoers 和自动挂载。

## Develop · 开发

1. Homebrew: `brew install ntfs-3g`
2. FUSE-T (build-time only, to extract `go-nfsv4` and `libfuse.2.dylib`).

```bash
./scripts/prepare-runtime.sh
./scripts/test-helper.sh
./scripts/build.sh
CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh
FUSE_T_REDISTRIBUTION_OK=1 ./scripts/package-dmg.sh   # only with a FUSE-T redistribution license
./scripts/package-dmg.sh                              # personal-use DMG (default)
```

See [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md) and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md). Shipping this app as a product requires a FUSE-T commercial license and Apple notarization.  
作为产品分发需要 FUSE-T 商业许可和 Apple 公证。

## License · 许可

**GPL-2.0-or-later** for the combined work with ntfs-3g. `go-nfsv4` remains under FUSE-T terms (personal use by default).  
与 ntfs-3g 合并后的作品为 GPL-2.0-or-later。`go-nfsv4` 仍按 FUSE-T 条款（默认仅个人使用）。
