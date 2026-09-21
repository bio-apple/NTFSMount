# NTFSMount

Read and write Windows (NTFS) drives on macOS. The menu bar icon is **NTFS**.

macOS mounts NTFS read-only. This app bundles **ntfs-3g** and a userspace FUSE stack inside `NTFSMount.app` — no kernel extension, no system FUSE-T at runtime.

**Plug in → Mount writable → Eject → unplug.**

## Install

1. Open `NTFSMount.dmg` (build it with `./scripts/package-dmg.sh` → `dist/NTFSMount.dmg`).
2. Drag **NTFSMount** to **Applications**.
3. Open it. The menu bar should show **NTFS**.
4. The first launch asks for an admin password to install the mount helper.

If macOS says the app cannot be opened: Control-click it → **Open**. Reinstall by dragging the app from the DMG again.

## Launch

There is no Dock icon — only the menu bar.

- Finder → **Applications** → **NTFSMount**
- Spotlight: `NTFSMount`
- `open /Applications/NTFSMount.app`

Success: **NTFS** appears in the menu bar. Use **Launch at login** in the menu to start it automatically. **Quit NTFS 读写** to exit; reopen with the steps above.

## Use

1. Plug in an NTFS drive.
2. Click **NTFS** in the menu bar.
3. Choose **Mount writable** (or **Mount all writable**).
4. Finder opens `/Volumes/<name>`. Copy, delete, rename as usual.
5. When done: **Eject (safe to unplug)** → wait until the disk disappears → unplug.

Do not unplug without ejecting. Skipping eject can leave the volume dirty and risk data loss.

| Menu | Meaning |
| --- | --- |
| **Unmount** | Unmount only; the cable stays in |
| **Eject (safe to unplug)** | Unmount and tell the system it is safe to unplug |

| Mark | State |
| --- | --- |
| ● | Writable — use Finder |
| ○ | macOS read-only — choose **Mount writable** |
| ◌ | Detected, not mounted — choose **Mount writable** |
| … | Busy |

Shut Windows down cleanly before removing the disk. A dirty volume may be force-mounted (hibernation file cleared); back up important data first.

If Finder shows both `Name` and `Name 1`, the `1` copy is usually the read-only system mount — use the writable one from this menu.

## Permissions

Only if something fails:

- **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → enable **NTFSMount**
- **Network Volumes**: System Settings → Privacy & Security → Files and Folders → enable **Network Volumes** (mounted but Finder shows nothing)

## Uninstall the app

```bash
./uninstall.sh
```

Removes the app, helper, and sudo rule. This does not eject a drive.

## Develop

```bash
./scripts/prepare-runtime.sh   # refresh bundled binaries in runtime/
./scripts/build.sh             # build NTFSMount.app
./scripts/package-dmg.sh       # dist/NTFSMount.dmg
```
