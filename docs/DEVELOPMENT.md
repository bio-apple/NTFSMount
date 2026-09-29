# Development

Build, test, and architecture notes. Not a contributing guide.

## Build and test

```bash
./scripts/check-fuse-deps.sh
swift test && ./scripts/test-helper.sh
./scripts/build.sh && ./scripts/package-pkg.sh
```

`check-fuse-deps.sh` checks the FUSE-T / ntfs-3g toolchain on an Apple Silicon dev machine. It may `brew install ntfs-3g`; it does not install macFUSE. **SIP stays enabled**; this app does not use a kernel extension.

Packaging, notarization, and GitHub Release rules: [DISTRIBUTION.md](./DISTRIBUTION.md). Sparkle (disabled on unnotarized builds): [SPARKLE.md](./SPARKLE.md).

## Architecture

Finder talks to the disk through userspace FUSE-T (`go-nfsv4`) and ntfs-3g. The app stays unprivileged; mount / unmount / format go to a LaunchDaemon over a Unix socket. Nothing is written to `sudoers`. SIP stays enabled; no kext.

Signed/notarized builds register the daemon with `SMAppService`. Ad-hoc builds fall back to Authorization Services (`kAuthorizationRightExecute`) for one-time helper install/uninstall — not `sudo` or `osascript`.

![Architecture](screenshots/architecture.svg)

**I/O path:** Finder → FUSE-T NFS (userspace) → `go-nfsv4` + ntfs-3g → the NTFS volume.

**Privilege path:** unprivileged menu-bar app → Unix socket v2 → `ntfsmount-helperd` (root, CDHash pin) → sealed `ntfs-rw-helper` → ntfs-3g. Hung-up clients are not executed.
