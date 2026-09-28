# NTFSMount

Menu-bar app for writable external NTFS on Apple Silicon (macOS 13+), in userspace — no kernel extension, **SIP stays enabled**.

> ⚠️ Personal use only, not notarized. Writing or formatting an NTFS disk can cause data loss; back up first. You must allow the app to run manually. FUSE-T `go-nfsv4` is not GPL; do not redistribute or sell.

**[Download DMG](https://github.com/bio-apple/NTFSMount/releases/latest/download/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/latest)

**Requirements:** Apple Silicon, macOS 13+, SIP on. Install in `/Applications`. No Homebrew, macFUSE, or extra FUSE-T.

## Quick Start

1. Download the DMG (GitHub Latest). Drag NTFSMount into Applications.
2. Control-click → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
3. Agree, then **Install…** the mount helper (admin password once).
4. Plug in an external NTFS disk → menu bar **NTFS** → **Mount Writable**.

## Screenshots

<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/menubar.png" alt="Menu bar"><br>Menu bar</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/window.png" alt="Window"><br>Window</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/settings.png" alt="Settings"><br>Settings</td>
</tr>
</table>

## Uninstall

1. Open the app → Settings → Remove Helper.
2. Drag NTFSMount to the Trash.
3. Optional full cleanup from a clone: `./uninstall.sh` (does not call `sudo`; does not touch system FUSE-T / MacFUSE).

## Help

- In the app: Diagnose Environment → Export Diagnostic Report and attach the zip to an [Issue](.github/ISSUE_TEMPLATE/bug_report.md).
- After an upgrade: replace the app, then **Update mount helper**.

## License

- Swift source: GPL-2.0-or-later ([LICENSE](./LICENSE))
- ntfs-3g: GPL-2.0-or-later
- FUSE-T component: its own license; do not redistribute or sell
- Overall app: not a single GPL; redistribution must follow [NOTICE](./NOTICE) and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)

[CHANGELOG.md](./CHANGELOG.md) · [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)
