# NTFSMount

[![build](https://github.com/bio-apple/NTFSMount/actions/workflows/build.yml/badge.svg)](https://github.com/bio-apple/NTFSMount/actions/workflows/build.yml)
[![ShellCheck](https://github.com/bio-apple/NTFSMount/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/bio-apple/NTFSMount/actions/workflows/shellcheck.yml)

> ⚠️ Pre-release, personal use only. Writing or formatting an NTFS disk can cause data loss; back up first. This app is not notarized; you must allow it to run manually. The FUSE-T component is not GPL; do not redistribute or sell.

NTFSMount is a personal-use pre-release menu-bar app for writable external NTFS on Apple Silicon (macOS 13+), in userspace — no kernel extension, **SIP stays enabled**.

**[Download DMG](https://github.com/bio-apple/NTFSMount/releases/latest/download/NTFSMount.dmg)** · [SHA256](https://github.com/bio-apple/NTFSMount/releases/latest)

## Requirements

- **macOS 13.0+** (Ventura or later). No upper bound is declared.
- **Apple Silicon** (arm64) only. Intel Macs are not supported.
- Keep **SIP enabled**. This app does not use a kernel extension.
- Install the `.app` in **`/Applications`**.
- An **administrator password once** to install the mount helper.
- End users do **not** need Homebrew, macFUSE, or a separate FUSE-T install. Do **not** `brew install macfuse` or `brew install fuse-t`.

## Install dependencies

End users: **none** beyond the DMG. The app already bundles FUSE-T and ntfs-3g.

Developers: Xcode and `swift test` — see [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## Quick Start

1. Download the DMG above (GitHub Latest, always the current release).
2. Drag NTFSMount into Applications. Control-click → **Open**, or System Settings → Privacy & Security → **Open Anyway**.
3. Agree, then **Install…** the mount helper (macOS Authorization Services admin dialog on this build; daily mount does not ask again).
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

Nothing is written to `sudoers`. **SIP stays enabled** (never disable it; this app does not use a kext). Settings → uninstall helper uses Authorization Services to run the copy inside the app (`Contents/Resources/uninstall-helper.sh`) and leaves the `.app` in place.

Uninstall: 1) Open the app → Settings → Remove Helper; 2) Drag NTFSMount to the Trash; 3) For a full cleanup, run `./uninstall.sh` from a **root** shell in the project directory (the app’s Uninstall Helper is the supported path; the script does not call `sudo`). It removes the LaunchDaemon and leftover configuration.

`./uninstall.sh` is the repo/project root script (not in the DMG or `.app`). Leftovers after it: `~/Library/Logs/ntfsmount.log` and `/Library/Logs/ntfsmount-helperd.log` (not deleted). UserDefaults `com.bioapple.ntfsmount` are removed. System FUSE-T / MacFUSE is not touched.

## Troubleshooting

- **Gatekeeper / unnotarized:** Control-click the app → **Open**, or System Settings → Privacy & Security → **Open Anyway**. If it is still quarantined: `xattr -d com.apple.quarantine /Applications/NTFSMount.app`.
- **Helper install / socket:** Click **Install…** (or **Update…**) in the app and enter the admin password. The helper listens on `/var/run/com.bioapple.ntfsmount.sock`. If install fails or the socket is missing, check `~/Library/Logs/ntfsmount.log` and `/Library/Logs/ntfsmount-helperd.log`.
- **Busy unmount:** Close Finder windows and files on that volume, then Eject / unmount again.
- **Hibernate / Fast Startup:** Windows left the volume hibernated or used Fast Startup. The app mounts **read-only**. Fully shut down Windows (no hibernate / Fast Startup) before mounting writable.
- **App not in `/Applications`:** Drag `NTFSMount.app` there; bundled ntfs-3g / FUSE-T is resolved from that path.
- **Report a bug:** in the app, Diagnose Environment → Export Diagnostic Report and attach the zip. Or from a clone, run `./scripts/ntfsmount diagnose --json` and paste the JSON into a [bug report](.github/ISSUE_TEMPLATE/bug_report.md). See [CONTRIBUTING.md](./CONTRIBUTING.md).

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

- Swift source: GPL-2.0-or-later ([LICENSE](./LICENSE))
- ntfs-3g: GPL-2.0-or-later
- FUSE-T component: its own license; do not redistribute or sell
- Overall app: not a single GPL; redistribution must follow [NOTICE](./NOTICE) and [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)

Mixed binary DMG compliance is not confirmed; a lawyer must confirm.

Changelog: [CHANGELOG.md](./CHANGELOG.md)
