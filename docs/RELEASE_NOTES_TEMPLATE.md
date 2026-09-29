# NTFSMount X.Y.Z

Personal-use pre-release. Not notarized. Do not mirror or treat as a product until FUSE-T written permission and Apple notarization. See NOTICE.

Apple Silicon + macOS 13.0+ only. GitHub **pre-release** (not Latest) unless the build is notarized **and** `FUSE_T_REDISTRIBUTION_OK=1`.

Optional override: copy this file to `docs/RELEASE_NOTES/<version>.md` (no `v` prefix) and fill every section from `git log` since the previous tag. Do not invent What’s new. Pushing a `v*` tag runs `scripts/generate-release-notes.sh`; generated notes are the GitHub Release body unless this file exists and is fully filled (no `_TBD` / `**Yes / No**`). CHANGELOG.md is still manual.

## What's new

- _TBD — fill from git log; do not invent._

## Fixes

- _TBD — fill from git log; do not invent._

## Breaking Changes

- _TBD — BREAKING / incompatible / HELPER_VERSION / reinstall helper; or write none._

## Changes

- _TBD — unmatched commits, or delete this section if unused._

## Known issues

- Unnotarized: Gatekeeper blocks first launch (Control-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Personal-use only (bundled FUSE-T). Do not mirror.
- This tag is a GitHub **pre-release** (not Latest) unless notarization and FUSE-T redistribution are both done.
- _TBD — add build-specific issues, or delete this bullet._

## Helper: reinstall required?

- **Yes / No**
- Why: IPC v? / `ntfs-rw-helper` SHA / `helper.stamp` / CDHash (`allowed.cdhash`) / `HELPER_VERSION=?`

## Old config compatibility

- **UserDefaults:** _TBD — keys kept, renamed, or migrated?_
- **Auto-mount:** _TBD — `autoMountUserOff` / LaunchDaemon plist names?_
- **Helper stamp:** _TBD — must `helper.stamp` / `allowed.cdhash` be rewritten?_
- **Leftover sudoers:** `/etc/sudoers.d/ntfs-rw` — still deleted on install/update/uninstall? Any leftover NOPASSWD?

## Verify the package

CI appends SHA256 after packaging. Do not invent a hash here.
