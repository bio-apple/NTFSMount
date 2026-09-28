# NTFSMount

**English** · [简体中文](./README_ZH.md)

Writable **external NTFS** on Apple Silicon Macs (macOS 13+). No kernel extension, no SIP change. Intel is not supported. The UI follows the system language (English / 简体中文 / 繁體中文 / 日本語).

**[Download v1.2.1 DMG](https://github.com/bio-apple/NTFSMount/releases/download/v1.2.1/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/tag/v1.2.1)

- **Back up first.** Writable mount or format can destroy data.
- **Not notarized.** Control-click the app → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
- **Personal use.** Bundled FUSE-T `go-nfsv4` is not GPL. Do not ship or sell until you have a written [FUSE-T](https://www.fuse-t.org/) license **and** Developer ID notarization. See [NOTICE](./NOTICE).

## Quick Start

1. Download the DMG above (this pre-release, not GitHub Latest).
2. Drag NTFSMount into Applications and open it as above.
3. Agree, then **Install…** the mount helper (admin password on this build). Remove it later from **Settings**; full uninstall: `./uninstall.sh`.
4. Plug in an external NTFS disk → menu bar **NTFS** → **Mount Writable**.

Closing the window keeps the menu-bar icon; Quit from the menu or Dock to exit.

## Screenshots

<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/menubar.png" alt="Menu bar"><br>Menu bar</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/window.png" alt="Window"><br>Window</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/settings.png" alt="Settings"><br>Settings</td>
</tr>
</table>

## Use

| Status | What to do |
| --- | --- |
| Writable | Use it |
| Read-only · system NTFS | Volume is clean; switch to writable from the submenu |
| Read-only · hibernate / unclean | Fully shut down Windows. Do not force writable |

Erase as NTFS is **whole external disks** only, from the root menu. Return defaults to **Cancel**. This app never silently deletes `hiberfil.sys`.

## FAQ

**Won’t open?** Control-click → Open. Last resort:

```bash
xattr -d com.apple.quarantine /Applications/NTFSMount.app
```

**Always asked for an admin password?** Expected on this un-notarized build.

**Install looks wrong?** Menu **Diagnose Environment…** (read-only; does not mount or install the helper).

## Architecture

Finder talks to the disk through userspace FUSE-T (`go-nfsv4`) and ntfs-3g. The app stays unprivileged; mount / unmount / format go to a LaunchDaemon over a Unix socket. Nothing is written to `sudoers`.

![Architecture](docs/screenshots/architecture.svg)

## Develop

```bash
./scripts/check-fuse-deps.sh
swift test && ./scripts/test-helper.sh
./scripts/build.sh && ./scripts/package-dmg.sh
```

## License

Swift and ntfs-3g in this repo are GPL-2.0-or-later ([LICENSE](./LICENSE)). `go-nfsv4` is excluded. Redistribution: [NOTICE](./NOTICE), [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).
