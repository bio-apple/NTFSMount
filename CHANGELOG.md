# Changelog

Personal-use. Not notarized. Do not mirror or treat as a product.

All notable **released** changes are listed here, newest first. Current GitHub tag: `v1.0.0` (`CFBundleShortVersionString` 1.0.0). Older `v1.2.0` / `v1.2.1` GitHub tags were withdrawn; their notes remain below as history.

## [Unreleased]

None.

## [1.0.0] - 2026-09-28

Build 4 of the same `1.0.0` tag. Marketing version stays `1.0.0`.

Version-number reset of the current personal-use tree. Includes the 1.2.1 feature set plus post-1.2.1 work that had not been tagged. Facts match [docs/RELEASE_NOTES/1.0.0.md](docs/RELEASE_NOTES/1.0.0.md).

### Added

- Optional Settings toggle to remove macOS junk (`.DS_Store`, AppleDouble `._*` files, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.TemporaryItems`) from a writable external NTFS volume before eject/unmount. Off by default.
- Safer unmount: `diskutil unmount force` only after the UI confirms a busy volume; otherwise busy is returned to the user.
- Helper `repair-env`: clear leftover numbered mount points / orphan localhost NFS without force-unmount, ntfsfix, or clearing hiberfile.
- Disk status rows in the window (mount mode, used space, encryption hint, journal).
- Force-unmount confirmation copy and format identity / final-warning policy in the UI.
- Auto-mount skips dirty / hibernated / corrupt volumes for writable attempts; consent is required before the helper runs.
- GitHub issue template, CONTRIBUTING, DEVELOPMENT, changelog, and generated release-notes scripts.
- CI runtime SHA256 check and structured release notes on `v*` tags.
- README download points at GitHub Latest (`NTFSMount.dmg`). In-app Sparkle stays off until notarized.
- About, Settings, and the menu-bar About item show `CFBundleShortVersionString` (1.0.0) via L10n.

### Fixed

- Eject/unmount busy copy names occupier processes (Finder, …) from helper `busy-occupiers`, truncated to three names plus “and N more”. When lsof cannot list them, generic busy stays and one line asks for Full Disk Access.
- Shell scripts such as `uninstall.sh` print English. Comments stay as they were.
- Helper install on macOS without `/usr/bin/realpath`.
- Helper `CommandPath` resolution when installing the LaunchDaemon.
- Diagnose no longer treats leftover macFUSE noise as a blocking error.
- Unmount no longer force-pops busy volumes without confirmation.

### Known issues

- Unnotarized: Gatekeeper blocks first launch (Control-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Personal-use only (bundled FUSE-T). Do not mirror or sell.
- Ad-hoc builds usually cannot register `SMAppService`; helper install falls back to an administrator password prompt.
- Download updates from GitHub Releases; in-app Sparkle stays off until notarized.

### Helper: reinstall required?

- **Yes.** After replacing the app, use **Update mount helper**. Required even if writable mounts still appear to work.
- Why: `HELPER_VERSION` 9 → 10 (`ntfs-rw-helper` SHA, `helper.stamp`, safer unmount, `repair-env`).
- Users who never installed 1.2.x still need a first helper install (IPC v2, CDHash pinning).

### Config compatibility

- **UserDefaults:** `com.bioapple.ntfsmount.*` keys are unchanged. First launch still migrates `local.ntfsmount.autoMountUserOff` and `local.ntfsmount.didShowCompatNotice` once (`didMigrate`).
- **Auto-mount:** `autoMountUserOff` is preserved. LaunchDaemon plist names are unchanged.
- **Helper stamp:** `/Library/Application Support/NTFSMount/helper.stamp` and `allowed.cdhash` must be rewritten by the helper installer (bundled SHA changed). `lastHelperSHA` updates after a successful install.
- **Leftover sudoers:** `/etc/sudoers.d/ntfs-rw` and `/usr/local/sbin/ntfs-rw-helper` are treated as stale. Install / update / uninstall helper deletes them. Do not keep NOPASSWD leftovers.

Published GitHub asset (`v1.0.0`) SHA256: `d4699aee3a724bc41b39561dd1e2a77a2ec13b3a04b0210598640c5a5241cd27` `NTFSMount.dmg`.

## [1.2.1] - 2026-09-28

Compared to 1.2.0 (`ee65e96` / tag `v1.2.0`). Facts match [docs/RELEASE_NOTES/1.2.1.md](docs/RELEASE_NOTES/1.2.1.md). Helper-install bullets under Fixed landed after `530d9f3`; drop them if the attached DMG predates those commits.

### Added

- Glanceable NTFS volume status on the menu-bar icon (hover card; the window can stay closed).
- Helper CDHash pinning (`allowed.cdhash`): the daemon trusts the app identity recorded at install, not only the `.app` currently on disk.
- In-app environment diagnose window.
- Helper IPC v2 (length-prefixed argv so volume labels may contain newlines). Format / ntfsfix wait up to 600s with NUL heartbeats; other commands 180s.
- Locales.
- Sparkle remains bundled for a future notarized build but is **not** started on this unnotarized package (no in-app “Check for Updates”).

### Fixed

- Helper install on macOS without `/usr/bin/realpath`.
- Helper `CommandPath` resolution when installing the LaunchDaemon.
- Diagnose no longer treats leftover macFUSE noise as a blocking error.

### Known issues

- Unnotarized: Gatekeeper blocks first launch (Control-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Personal-use only (bundled FUSE-T). Do not mirror.
- This tag is a GitHub **pre-release** (not Latest).
- Ad-hoc builds usually cannot register `SMAppService`; helper install falls back to an administrator password prompt.
- Download updates from GitHub Releases; in-app Sparkle stays off until notarized.

### Helper: reinstall required?

- **Yes.** After replacing the app, use **Update mount helper**. Required even if writable mounts still appear to work.
- Why:
  - `HELPER_VERSION` 6 → 9 (`ntfs-rw-helper` SHA and `helper.stamp`).
  - New `ntfsmount-helperd`: IPC v2 and CDHash pinning (`allowed.cdhash`).
  - A replaced `.app` that is not re-registered fails caller checks against the CDHash written at install.
- The app may fall back to IPC v1 if an old daemon returns a protocol error; that is not a substitute for reinstall.

### Config compatibility

- **UserDefaults:** `com.bioapple.ntfsmount.*` keys are unchanged. First launch still migrates `local.ntfsmount.autoMountUserOff` and `local.ntfsmount.didShowCompatNotice` once (`didMigrate`).
- **Auto-mount:** `autoMountUserOff` is preserved. LaunchDaemon plist names are unchanged.
- **Helper stamp:** `/Library/Application Support/NTFSMount/helper.stamp` and `allowed.cdhash` must be rewritten by the helper installer (bundled SHA / CDHash changed). `lastHelperSHA` updates after a successful install.
- **Leftover sudoers:** `/etc/sudoers.d/ntfs-rw` and `/usr/local/sbin/ntfs-rw-helper` are treated as stale. Install / update / uninstall helper deletes them. Do not keep NOPASSWD leftovers.

Published GitHub asset (`v1.2.1`) SHA256: `fa9ee0f20f22946691fd1f0813c0ef1cc6ebd43b0a9b5949981ecb25512597a9` `NTFSMount.dmg`.

## [1.2.0] - 2026-09-24

First git tag (`v1.2.0` = `ee65e96`). No `docs/RELEASE_NOTES/1.2.0.md`. Below is `git log` at that tag only (`HELPER_VERSION=6`, `CFBundleShortVersionString` 1.2.0).

### Added

- Menu-bar app for writable external NTFS on Apple Silicon (macOS 13+), userspace FUSE-T + bundled ntfs-3g.
- Native volume window and menu-bar **NTFS** controls (mount / unmount / eject / format).
- Signature-pinned privileged helper daemon (LaunchDaemon); no `sudoers` NOPASSWD.
- NTFS format for external whole disks (confirm the current volume name; Return cancels).
- Auto-mount on by default; no login-at-startup. Internal / Boot Camp disks are not auto-mounted.
- CLI diagnose (`./scripts/ntfsmount diagnose`) without mounting or installing the helper.

### Fixed

- Hardened helper eject and dirty-volume repair (ntfsfix consent; safer path quoting).
- FUSE-T runtime pinned; CI plus docs aimed at a future notarized release.

### Known issues

- Unnotarized: Gatekeeper blocks first launch (Control-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Personal-use only (bundled FUSE-T). Do not mirror.
- GitHub **pre-release** only; do not use Latest (that README rule was later changed on `main` after 1.2.1).
- Ad-hoc builds usually cannot register `SMAppService`; helper install falls back to an administrator password prompt.

### Helper: reinstall required?

- **Yes** if you had an older untagged build that used `/etc/sudoers.d/ntfs-rw`. This release uses the signature-pinned daemon (`HELPER_VERSION=6`), not sudoers.
- Install / update / uninstall helper is expected to remove leftover sudoers. Do not keep NOPASSWD leftovers.

### Config compatibility

- Preferences: `com.bioapple.ntfsmount` UserDefaults.
- Auto-mount preference is user-toggleable (`autoMountUserOff` in later notes); LaunchDaemon plist: `com.bioapple.ntfsmount.helper`.
- Helper files under `/Library/Application Support/NTFSMount/` and socket `/var/run/com.bioapple.ntfsmount.sock`.

[Unreleased]: https://github.com/bio-apple/NTFSMount/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bio-apple/NTFSMount/releases/tag/v1.0.0
[1.2.1]: https://github.com/bio-apple/NTFSMount/blob/main/docs/RELEASE_NOTES/1.2.1.md
[1.2.0]: https://github.com/bio-apple/NTFSMount/commit/ee65e96b934d1aeaa7bfddc465df8e96d2fed434
