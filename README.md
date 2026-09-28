# NTFSMount

Writable **external NTFS** on Apple Silicon Macs (macOS 13+). No kernel extension, no SIP change. Intel is not supported. The UI follows the system language (English / 简体中文 / 繁體中文 / 日本語).

**[Download DMG](https://github.com/bio-apple/NTFSMount/releases/latest/download/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/latest)

- **Back up first.** Writable mount or format can destroy data.
- **Not notarized.** Control-click the app → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
- **Personal use.** Bundled FUSE-T `go-nfsv4` is not GPL. Do not ship or sell until you have a written [FUSE-T](https://www.fuse-t.org/) license **and** Developer ID notarization. See [NOTICE](./NOTICE).

## Quick Start

1. Download the DMG above (GitHub Latest, always the current release).
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

## Compared with

| | NTFSMount | Paragon NTFS for Mac | Microsoft NTFS for Mac by Tuxera | Mounty |
| --- | --- | --- | --- | --- |
| Cost | Free personal-use pre-release | Paid commercial | Paid commercial | Free (older) |
| Macs | Apple Silicon, macOS 13+ | Intel + Apple Silicon (typical) | Broader Mac support (typical) | Historically broader |
| Stack | Userspace FUSE-T (`go-nfsv4`) + bundled GPL ntfs-3g; LaunchDaemon; menu bar (mount / format / diagnose); no kext, SIP on | Commercial signed driver; drop-in volume support | Commercial signed driver (not open-source ntfs-3g) | Commonly macFUSE kext + ntfs-3g |
| Shipping | Not notarized; not App Store / not official Homebrew. FUSE-T is **not** GPL | Typically notarized | Typically notarized | — |

- NTFSMount uses **open-source ntfs-3g**, not Tuxera’s commercial driver — not the same license, support, or product.
- Runtime is bundled in the app. Versus Mounty, that means Apple Silicon only, FUSE-T personal use, and an unnotarized build.

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
