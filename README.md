# NTFSMount

Read and write Windows (NTFS) drives on macOS. Menu bar title: **NTFS**.

macOS mounts NTFS read-only. This app bundles **ntfs-3g**, **mkntfs**, and a userspace FUSE stack inside `NTFSMount.app` — no kernel extension, no system FUSE-T at runtime.

**Plug in → 以可写方式挂载 → 推出（可安全拔出） → unplug.**

## Install

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

**开机启动** in the menu starts it at login. **退出 NTFS 读写** quits; reopen with the steps above.

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

## Format as NTFS

Erases an **external** whole disk and creates one NTFS volume. Internal, system, and disk-image volumes are refused.

1. **NTFS** → **格式化为 NTFS…** (also on a disk’s submenu).
2. Confirm. Optionally change the volume name. Default button is **取消**.
3. **抹掉并格式化**. This deletes everything on that disk.
4. When it finishes, the app remounts the new volume writable.

## Permissions

Only if something fails:

- **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → enable **NTFSMount**
- **Network Volumes**: System Settings → Privacy & Security → Files and Folders → enable **Network Volumes** (mounted but Finder shows nothing)

## Uninstall

```bash
./uninstall.sh
```

Quits the app and removes `/Applications/NTFSMount.app`, the helper, and the sudo rule. This does not eject a drive.

## Develop

```bash
./scripts/prepare-runtime.sh   # refresh bundled binaries in runtime/
./scripts/build.sh             # build NTFSMount.app
./scripts/package-dmg.sh       # dist/NTFSMount.dmg
```
