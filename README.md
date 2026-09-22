# NTFSMount

Read and write Windows (NTFS) drives on macOS. Menu bar title: **NTFS**.

**当前仅支持 Apple Silicon (M芯片) 及 macOS 13.0+**

macOS mounts NTFS read-only. This app bundles **ntfs-3g**, **mkntfs**, and a userspace FUSE stack inside `NTFSMount.app` — no kernel extension, no system FUSE-T at runtime. Packaged DMG/app users do not need FUSE-T installed; a FUSE-T install is only required when building from source (see Develop).

This project is **GPL-2.0-or-later**. It ships ntfs-3g (GPL), so the combined work — including the Swift sources — is offered under the same terms. See [LICENSE](./LICENSE) and [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).

**Plug in → 以可写方式挂载 → 推出（可安全拔出） → unplug.**

## Disclaimer

**免责声明：使用第三方驱动修改 NTFS 挂载权限存在数据损坏风险，请确保重要数据已提前备份。**

Writing to NTFS from macOS via a third-party driver can corrupt the volume. Back up anything important before mounting writable or formatting.

## Install

当前仅支持 Apple Silicon (M芯片) 及 macOS 13.0+

1. Open `dist/NTFSMount.dmg` (build with `./scripts/package-dmg.sh`).
2. Drag **NTFSMount** to **Applications**.
3. Open it. The menu bar should show **NTFS**.
4. First launch asks for an admin password to install the mount helper.

If macOS says the app cannot be opened: Control-click it → **Open**. Reinstall by dragging from the DMG again.

After an update, the app may ask to **更新挂载助手** (one admin password). Do that before formatting.

## Launch

No Dock icon — menu bar only.

- Finder → **Applications** → **NTFSMount**
- Spotlight: `NTFSMount`
- `open /Applications/NTFSMount.app`

**开机启动** in the menu starts it at login. **插入时自动挂载** installs a LaunchDaemon that remounts NTFS disks writable when they appear. **退出 NTFS 读写** quits; reopen with the steps above.

## Mount and eject

1. Plug in an NTFS drive.
2. Click **NTFS** in the menu bar.
3. On the disk: **以可写方式挂载** (or **全部以可写方式挂载**).
4. Finder opens `/Volumes/<name>`. Copy, delete, rename as usual.
5. When done: **推出（可安全拔出）** → wait until the disk disappears → unplug.

Do not unplug without ejecting. That can leave a dirty volume and risk data loss. Shut Windows down cleanly before unplugging there, too.

| Menu | Meaning |
| --- | --- |
| **以可写方式挂载** | Remount writable |
| **在访达中打开** | Open the mount in Finder |
| **卸载** | Unmount; cable stays in |
| **推出（可安全拔出）** | Unmount and mark safe to unplug |
| **刷新** | Rescan disks |

| Mark | State |
| --- | --- |
| ● | Writable — use Finder |
| ○ | macOS read-only — choose **以可写方式挂载** |
| ◌ | Detected, not mounted — choose **以可写方式挂载** |
| … | Busy |

If Finder shows both `Name` and `Name 1`, the `1` copy is usually the read-only system mount. Use the writable volume from this menu.

A dirty volume may be force-mounted (hibernation file cleared). Back up important data first.

## Auto-mount on insert

**插入时自动挂载：开** installs `/Library/LaunchDaemons/local.ntfsmount.automount.plist` (admin password once).

The daemon watches `/Volumes` (`WatchPaths`) and also runs on filesystem mounts (`StartOnMount`). When macOS attaches an NTFS volume read-only, it remounts that volume writable. Disks you have already **卸载** stay unmounted. Internal/system disks are never formatted; this path only mounts.

Turn it **关** to unload the daemon and remove the plist. `./uninstall.sh` removes it as well.

## Format as NTFS

Erases an **external** whole disk and creates one NTFS volume. Internal, system, and disk-image volumes are refused.

1. **NTFS** → **格式化为 NTFS…** (also on a disk’s submenu).
2. Confirm. Optionally change the volume name. Default button is **取消**.
3. **抹掉并格式化**. This deletes everything on that disk.
4. When it finishes, the app remounts the new volume writable.

## Permissions

macOS 13+ 使用用户态 FUSE，不需要也不应安装内核扩展。

Only if something fails:

- **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → enable **NTFSMount**
- **Network Volumes**: System Settings → Privacy & Security → Files and Folders → enable **Network Volumes** (mounted but Finder shows nothing)

## Uninstall

```bash
./uninstall.sh
```

Quits the app and removes `/Applications/NTFSMount.app`, the helper, the sudo rule, and the auto-mount LaunchDaemon. This does not eject a drive.

## Develop

### 构建依赖 (Build Dependencies)
在运行构建脚本前，请确保已安装：
1. Homebrew: `brew install ntfs-3g`
2. FUSE-T (仅需在构建时提取 `go-nfsv4` 和 `libfuse.2.dylib` shim，运行时不依赖其系统服务)。

`./scripts/prepare-runtime.sh` copies `ntfs-3g` / `libntfs-3g` from the system (typically Homebrew) and `go-nfsv4` from `/Library/Application Support/fuse-t/bin/go-nfsv4-1.2.7` or `/usr/local/bin/go-nfsv4`, and requires `runtime/libfuse.2.dylib` (FUSE-T shim). End users of the packaged app still do not need a system FUSE-T install.

```bash
./scripts/prepare-runtime.sh   # refresh bundled binaries in runtime/
./scripts/build.sh             # build NTFSMount.app
./scripts/package-dmg.sh       # dist/NTFSMount.dmg
```

## License

**GPL-2.0-or-later.** See [LICENSE](./LICENSE) and [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md).

NTFSMount distributes **ntfs-3g**, **mkntfs**, and **libntfs-3g** (GNU GPL). Because those binaries are bundled with this app, the combined work — including the Swift UI, helper scripts, and packaging in this repository — is licensed under the GNU GPL version 2 or, at your option, any later version.

Bundled third-party components remain under their upstream licenses:

| Component | Upstream |
| --- | --- |
| ntfs-3g, mkntfs, libntfs-3g | GPL-2.0 (Tuxera ntfs-3g) |
| libfuse.2.dylib | LGPL-2.1 (FUSE-T shim) |
| go-nfsv4 | FUSE-T (see [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)) |

This is not legal advice. If you need a MIT-only or proprietary distribution, do not ship these GPL binaries; have users install ntfs-3g themselves (for example via Homebrew).
