# NTFSMount

[![build](https://github.com/bio-apple/NTFSMount/actions/workflows/build.yml/badge.svg)](https://github.com/bio-apple/NTFSMount/actions/workflows/build.yml)
[![ShellCheck](https://github.com/bio-apple/NTFSMount/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/bio-apple/NTFSMount/actions/workflows/shellcheck.yml)

> ⚠️ Pre-release, personal use only. Writing or formatting an NTFS disk can cause data loss; back up first. This app is not notarized; you must allow it to run manually. The FUSE-T component is not GPL; do not redistribute or sell.

NTFSMount is a personal-use pre-release menu-bar app for writable external NTFS on Apple Silicon (macOS 13+), in userspace — no kernel extension, no SIP change.

**[Download DMG](https://github.com/bio-apple/NTFSMount/releases/latest/download/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/latest)

## Quick Start

1. Download the DMG above (GitHub Latest, always the current release).
2. Drag NTFSMount into Applications. Control-click → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
3. Agree, then **Install…** the mount helper (admin password on this build).
4. Plug in an external NTFS disk → menu bar **NTFS** → **Mount Writable**.

Closing the window keeps the menu-bar icon; Quit from the menu or Dock to exit. UI language follows the system (English / Simplified Chinese / Traditional Chinese / Japanese). Intel Macs are not supported.

## Screenshots

<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/menubar.png" alt="Menu bar"><br>Menu bar</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/window.png" alt="Window"><br>Window</td>
<td align="center" valign="top" width="33%"><img src="docs/screenshots/settings.png" alt="Settings"><br>Settings</td>
</tr>
</table>

## Install / remove

**Install drops**

| What | Where |
| --- | --- |
| App | `/Applications/NTFSMount.app` |
| LaunchDaemon | `/Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist` |
| helperd | `/Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd` |
| Helper files | `/Library/Application Support/NTFSMount/` |
| Socket | `/var/run/com.bioapple.ntfsmount.sock` |
| Preferences | `com.bioapple.ntfsmount` UserDefaults |
| Logs | `~/Library/Logs/ntfsmount.log`, `/Library/Logs/ntfsmount-helperd.log` |

Nothing is written to `sudoers`. Settings → uninstall helper runs the copy inside the app (`Contents/Resources/uninstall-helper.sh`) and leaves the `.app` in place.

Uninstall: 1) Open the app → Settings → Remove Helper; 2) Drag NTFSMount to the Trash; 3) For a full cleanup, run `./uninstall.sh` from the project directory (administrator password required); it removes the LaunchDaemon and leftover configuration.

`./uninstall.sh` is the repo/project root script (not in the DMG or `.app`). Leftovers after it: `~/Library/Logs/ntfsmount.log` and `/Library/Logs/ntfsmount-helperd.log` (not deleted). UserDefaults `com.bioapple.ntfsmount` are removed. System FUSE-T / MacFUSE is not touched.

<details>
<summary>Compared with Paragon / Tuxera / Mounty</summary>

| | NTFSMount | Paragon NTFS for Mac | Microsoft NTFS for Mac by Tuxera | Mounty |
| --- | --- | --- | --- | --- |
| Cost | Free personal-use pre-release | Paid commercial | Paid commercial | Free (older) |
| Macs | Apple Silicon, macOS 13+ | Intel + Apple Silicon (typical) | Broader Mac support (typical) | Historically broader |
| Stack | Userspace FUSE-T + bundled ntfs-3g; no kext | Commercial signed driver | Commercial signed driver | Commonly macFUSE kext + ntfs-3g |
| Shipping | Not App Store / not official Homebrew | Commercial installer | Commercial installer | — |

NTFSMount uses **open-source ntfs-3g**, not Tuxera’s commercial driver — not the same license, support, or product. Runtime is bundled; versus Mounty that means Apple Silicon only and FUSE-T personal-use terms.

</details>

Development: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)

## License

The `.app` is mixed-license, not GPL as a whole. Swift sources in this repo and bundled ntfs-3g are GPL-2.0-or-later ([LICENSE](./LICENSE)); FUSE-T `go-nfsv4` is excluded. Redistribution: [NOTICE](./NOTICE), [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md).

Changelog: [CHANGELOG.md](./CHANGELOG.md)
