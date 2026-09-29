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

Finder talks to the disk through userspace FUSE-T (`go-nfsv4`) and ntfs-3g. The app stays unprivileged; probe / mount / unmount / eject / format / fix run as a root **child of the app** through Authorization Services, while auto-mount goes to a LaunchDaemon over a Unix socket. Nothing is written to `sudoers`. SIP stays enabled; no kext.

The child-process detail matters for macOS privacy: TCC attributes Full Disk Access to the responsible process, so a root child of the app inherits the app's grant, while a LaunchDaemon is its own subject and needs its own. Raw-device work (ntfs-3g / mkntfs / ntfsfix) fails with `Operation not permitted` without it.

Signed/notarized builds register the daemon with `SMAppService`. Ad-hoc builds fall back to Authorization Services (`kAuthorizationRightExecute`) for one-time helper install/uninstall — not `sudo` or `osascript`.

![Architecture](screenshots/architecture.svg)

**I/O path:** Finder → FUSE-T NFS (userspace) → `go-nfsv4` + ntfs-3g → the NTFS volume.

**Privilege path (on demand):** menu-bar app → Authorization Services (`kAuthorizationRightExecute`) → `ntfsmount-helperd exec-root` as the app's child → sealed `ntfs-rw-helper` → ntfs-3g / mkntfs / ntfsfix.

`exec-root` calls `setgid(0)`/`setuid(0)` before exec, so the child is real root like `sudo`. Authorization Services only raises the effective uid, and ntfs-3g refuses to mount when `getuid() != geteuid()` with an external FUSE library.

**Auto-mount:** app-side. `DiskWatch` (DiskArbitration) wakes a scan, and eligible external NTFS volumes are queued through the same mount path the menu uses — so auto-mount inherits the app's Full Disk Access and no root daemon is involved. A leftover LaunchDaemon from older builds is removed by `install-helper.sh`.
