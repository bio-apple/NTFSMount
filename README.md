# NTFSMount · NTFS 读写

[Download the DMG](https://github.com/bio-apple/NTFSMount/releases) · [下载 DMG](https://github.com/bio-apple/NTFSMount/releases)

Read and write Windows (NTFS) drives on macOS. Menu bar: **NTFS**. App name: **NTFS 读写**. Package: `NTFSMount.app`. Direct distribution (not Mac App Store).  
在 macOS 上读写 Windows（NTFS）硬盘。菜单栏 **NTFS**，应用名 **NTFS 读写**，安装包 `NTFSMount.app`。Developer ID 直发，不上 Mac App Store。

**Apple Silicon (M series) and macOS 13.0+ only.**  
**当前仅支持 Apple Silicon（M 芯片）及 macOS 13.0+。**

macOS mounts NTFS read-only. This app bundles **ntfs-3g**, **mkntfs**, and a userspace FUSE stack inside `NTFSMount.app` — no kernel extension, no system FUSE-T at runtime. Packaged DMG/app users do not need FUSE-T installed; FUSE-T is only required when building from source (see Develop).  
macOS 默认把 NTFS 挂成只读。本应用把 **ntfs-3g**、**mkntfs** 和用户态 FUSE 打进 `NTFSMount.app`：不用内核扩展，运行时也不依赖系统里的 FUSE-T。用 DMG/应用的用户不必再装 FUSE-T；只有从源码构建时才需要（见「开发」）。

This project is **GPL-2.0-or-later**. It ships ntfs-3g (GPL), so the combined work — including the Swift sources — is offered under the same terms. See [LICENSE](./LICENSE) and [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).  
本项目为 **GPL-2.0-or-later**。因捆绑了 GPL 的 ntfs-3g，合并作品（含 Swift 源码）按相同条款提供。详见 [LICENSE](./LICENSE) 与 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。

**Plug in → writable by default → 推出（可安全拔出） → unplug.**  
**插入硬盘 → 默认以可写方式挂载 → 推出（可安全拔出） → 再拔线。**

## Disclaimer · 免责声明

**Using a third-party driver to change NTFS mount permissions can corrupt data. Back up anything important first.**  
**使用第三方驱动修改 NTFS 挂载权限存在数据损坏风险，请确保重要数据已提前备份。**

Writing to NTFS from macOS via a third-party driver can corrupt the volume. Back up before mounting writable or formatting.  
通过第三方驱动在 macOS 上写 NTFS 可能损坏卷。以可写方式挂载或格式化前请先备份。

## Install · 安装

Apple Silicon and macOS 13.0+ only.  
当前仅支持 Apple Silicon（M 芯片）及 macOS 13.0+。

1. Open `dist/NTFSMount.dmg` (build with `./scripts/package-dmg.sh`).  
   打开 `dist/NTFSMount.dmg`（用 `./scripts/package-dmg.sh` 生成）。
2. Drag **NTFSMount** to **Applications**.  
   把 **NTFSMount** 拖到「应用程序」。
3. Open it. The menu bar should show **NTFS**.  
   打开应用，菜单栏应出现 **NTFS**。
4. First launch opens the window. Install the helper from the banner (one admin password). Auto-mount on insert is then enabled for **external** disks only.  
   第一次启动会打开窗口。在横幅安装挂载助手（一次管理员密码）。之后仅对外置盘默认打开「插入时自动挂载」。

A notarized build opens normally. If macOS says the app cannot be opened, the DMG was not notarized: Control-click → **Open**.  
已公证的包可直接打开。若提示无法打开，说明该 DMG 未公证：按住 Control 点应用 → 打开。

After an update, the app may ask to **更新挂载助手** (one admin password). Do that before formatting.  
升级后可能提示 **更新挂载助手**（再输一次管理员密码）。格式化前请先更新。

## Launch · 启动

No Dock icon — menu bar only.  
没有程序坞图标，只在菜单栏。

- Finder → **Applications** → **NTFSMount**  
  访达 → **应用程序** → **NTFSMount**
- Spotlight: `NTFSMount`  
  聚焦搜索：`NTFSMount`
- `open /Applications/NTFSMount.app`

**插入时自动挂载** is on by default after the helper is installed; **external** NTFS disks remount writable when they appear. Internal / Boot Camp volumes are not auto-mounted. Optional **登录时打开** and **在程序坞显示**. **退出 NTFS 读写** quits.  
安装助手后 **插入时自动挂载** 默认打开，插入**外置** NTFS 盘会自动变成可写。内置盘 / Boot Camp 不会自动挂。可选 **登录时打开** 与 **在程序坞显示**。**退出 NTFS 读写** 会退出应用。

## Mount and eject · 挂载与推出

1. Plug in an NTFS drive. With **插入时自动挂载** on (the default), it remounts writable.  
   插入 NTFS 硬盘。默认打开 **插入时自动挂载**，会自动变成可写。
2. Click **NTFS** in the menu bar.  
   点菜单栏 **NTFS**。
3. If it is still read-only, click the disk name to **以可写方式挂载**.  
   若仍是只读，点盘名即可 **以可写方式挂载**。
4. Finder opens `/Volumes/<name>`. Copy, delete, rename as usual.  
   访达打开 `/Volumes/<卷名>`，可照常复制、删除、重命名。
5. When done: **推出（可安全拔出）** → wait until the disk disappears → unplug.  
   用完点 **推出（可安全拔出）** → 等盘从访达消失 → 再拔线。

Do not unplug without ejecting. That can leave a dirty volume and risk data loss. Shut Windows down cleanly before unplugging there, too.  
不要不推出就拔线，卷可能变脏并有丢数据风险。在 Windows 上也请正常关机后再拔。

| Menu · 菜单 | Meaning · 含义 |
| --- | --- |
| **以可写方式挂载** | Remount writable / 以可写方式重新挂载 |
| **在访达中打开** | Open the mount in Finder / 在访达中打开挂载点 |
| **卸载** | Unmount; cable stays in / 卸载，线不用拔 |
| **推出（可安全拔出）** | Unmount and mark safe to unplug / 卸载并标记可安全拔出 |
| **刷新** | Rescan disks / 重新扫描磁盘 |

| Mark · 标记 | State · 状态 |
| --- | --- |
| ● | Writable — use Finder / 可写，用访达即可 |
| ○ | macOS read-only — click the disk name / 系统只读，点盘名即可挂上 |
| ◌ | Detected, not mounted — click the disk name / 已检测到未挂载，点盘名即可挂上 |
| … | Busy / 正在处理 |

If Finder would otherwise show both `Name` and `Name 1`, the helper unmounts the macOS read-only mount (and a leftover `Name 1` from the same disk) before remounting, so the writable volume reuses `/Volumes/Name`.  
若访达会同时出现 `Name` 和 `Name 1`，助手会先卸掉系统只读挂载（以及同盘残留的 `Name 1`）再可写重挂，使可写卷仍用 `/Volumes/Name`。

If the volume is dirty or Windows is hibernated, it is mounted **read-only** and you are notified. Shut Windows down fully (not hibernate / fast startup) before a writable mount. The hibernation file is not deleted.  
卷不干净或 Windows 处于休眠时，会只读挂载并通知你。要可写请先让 Windows 完全关机（不要休眠 / 快速启动）。不会删除休眠文件。

## Auto-mount on insert · 插入时自动挂载

Installing the helper turns **插入时自动挂载** on by default (`/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist`). Internal disks and disk images are skipped.  
安装助手后默认打开 **插入时自动挂载**（`/Library/LaunchDaemons/com.bioapple.ntfsmount.automount.plist`）。内置盘和磁盘映像会被跳过。

The daemon watches `/Volumes` (`WatchPaths`) and also runs on filesystem mounts (`StartOnMount`). When macOS attaches an NTFS volume read-only, it unmounts that system mount and remounts writable (or read-only if the volume is dirty / hibernated). Disks you have already **卸载** stay unmounted. Internal/system disks are never formatted; this path only mounts.  
守护进程监视 `/Volumes`（`WatchPaths`），并在文件系统挂载时运行（`StartOnMount`）。系统把 NTFS 只读挂上后，它会卸掉该挂载再以可写方式挂上（脏盘 / 休眠则只读）。你已经 **卸载** 的盘不会再自动挂。此路径只负责挂载，不会格式化内置盘 / 系统盘。

Turn it **关** in the menu to unload the daemon and remove the plist. `./uninstall.sh` removes it as well. There is no **开机启动** option.  
在菜单里关掉即可卸载守护进程并删除 plist。`./uninstall.sh` 也会去掉。没有 **开机启动**。

## Format as NTFS · 格式化为 NTFS

Erases an **external** whole disk and creates one NTFS volume. Internal, system, and disk-image volumes are refused.  
抹掉一块**外置整盘**并做成一个 NTFS 卷。内置盘、系统盘、磁盘映像会被拒绝。

1. **NTFS** → **格式化为 NTFS…** (also on a disk’s submenu).  
   **NTFS** → **格式化为 NTFS…**（磁盘子菜单里也有）。
2. Confirm by typing the **current volume name**. Optionally change the new volume name. Default button is **取消**.  
   输入**当前卷名**确认。可改新卷名。默认按钮是 **取消**。
3. **抹掉并格式化**. This deletes everything on that disk.  
   **抹掉并格式化**。盘上全部文件都会删除。
4. When it finishes, the app remounts the new volume writable.  
   完成后应用会把新卷以可写方式挂上。

## Permissions · 权限

macOS 13+ uses userspace FUSE. Do not install a kernel extension.  
macOS 13+ 使用用户态 FUSE，不需要也不应安装内核扩展。

Only if something fails / 仅在出错时：

- **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → enable **NTFSMount**  
  **完全磁盘访问权限**：系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 打开 **NTFSMount**
- **Network Volumes**: System Settings → Privacy & Security → Files and Folders → enable **Network Volumes** (mounted but Finder shows nothing)  
  **网络卷**：系统设置 → 隐私与安全性 → 文件和文件夹 → 打开 **网络卷**（已挂上但访达看不到时）

## Uninstall · 卸载

```bash
./uninstall.sh
```

Quits the app and removes `/Applications/NTFSMount.app`, the helper, the sudo rule, and the auto-mount LaunchDaemon. This does not eject a drive.  
退出应用，并删除 `/Applications/NTFSMount.app`、挂载助手、sudo 规则和自动挂载 LaunchDaemon。不会推出已经插入的硬盘。

## Develop · 开发

### Build dependencies · 构建依赖

Before running the build scripts, install:

1. Homebrew: `brew install ntfs-3g`
2. FUSE-T (build-time only, to extract `go-nfsv4` and the `libfuse.2.dylib` shim; the packaged app does not need its system service).

运行构建脚本前请先安装：

1. Homebrew：`brew install ntfs-3g`
2. FUSE-T（仅构建时用来提取 `go-nfsv4` 和 `libfuse.2.dylib` shim，打包后的应用不依赖其系统服务）。

`./scripts/prepare-runtime.sh` copies `ntfs-3g` / `libntfs-3g` from the system (typically Homebrew) and `go-nfsv4` from `/Library/Application Support/fuse-t/bin/go-nfsv4-1.2.7` or `/usr/local/bin/go-nfsv4`, and requires `runtime/libfuse.2.dylib` (FUSE-T shim). End users of the packaged app still do not need a system FUSE-T install.  
`./scripts/prepare-runtime.sh` 从系统（一般为 Homebrew）拷贝 `ntfs-3g` / `libntfs-3g`，并从 `/Library/Application Support/fuse-t/bin/go-nfsv4-1.2.7` 或 `/usr/local/bin/go-nfsv4` 拷贝 `go-nfsv4`，且需要 `runtime/libfuse.2.dylib`（FUSE-T shim）。使用打包应用的最终用户仍不必安装系统 FUSE-T。

```bash
./scripts/prepare-runtime.sh   # refresh bundled binaries in runtime/ · 刷新 runtime/ 捆绑二进制
./scripts/test-helper.sh       # identifier selftest · 助手自检
./scripts/build.sh             # build NTFSMount.app · 编译应用
CODESIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… ./scripts/notarize.sh
./scripts/package-dmg.sh       # dist/NTFSMount.dmg · 打包 DMG
```

See [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md). FUSE-T `go-nfsv4` is free for personal use; shipping this app as a product may require a commercial license from the FUSE-T authors.  
发布检查见 [docs/RELEASE_CHECKLIST.md](./docs/RELEASE_CHECKLIST.md)。FUSE-T 的 `go-nfsv4` 个人使用免费；作为产品分发可能需要 FUSE-T 商业许可。

## License · 许可

**GPL-2.0-or-later.** See [LICENSE](./LICENSE) and [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).  
**GPL-2.0-or-later。** 见 [LICENSE](./LICENSE) 与 [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)。

NTFSMount distributes **ntfs-3g**, **mkntfs**, and **libntfs-3g** (GNU GPL). Because those binaries are bundled with this app, the combined work — including the Swift UI, helper scripts, and packaging in this repository — is licensed under the GNU GPL version 2 or, at your option, any later version.  
NTFSMount 分发 **ntfs-3g**、**mkntfs** 和 **libntfs-3g**（GNU GPL）。这些二进制与应用捆绑，因此本仓库的合并作品（含 Swift 界面、助手脚本和打包脚本）按 GNU GPL 第 2 版或（由你选择）任何更新版本授权。

Bundled third-party components remain under their upstream licenses:

捆绑的第三方组件仍遵循其上游许可：

| Component · 组件 | Upstream · 上游 |
| --- | --- |
| ntfs-3g, mkntfs, libntfs-3g | GPL-2.0 (Tuxera ntfs-3g) |
| libfuse.2.dylib | LGPL-2.1 (FUSE-T shim) |
| go-nfsv4 | FUSE-T (see [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)) |

This is not legal advice. If you need a MIT-only or proprietary distribution, do not ship these GPL binaries; have users install ntfs-3g themselves (for example via Homebrew).  
以上不构成法律意见。若需要仅 MIT 或专有分发，请不要捆绑这些 GPL 二进制，改为让用户自行安装 ntfs-3g（例如通过 Homebrew）。
