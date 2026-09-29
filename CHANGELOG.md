# Changelog

Personal-use. Not notarized. Do not mirror or treat as a product.

The only published release is **v1.0** (`CFBundleShortVersionString` 1.0).

## [1.0] - 2026-09-29

Menu-bar app for read/write external NTFS on Apple Silicon (macOS 13+). Userspace FUSE-T and ntfs-3g. SIP stays on. No kernel extension.

- Download is `NTFSMount.pkg`. The installer puts the app in `/Applications` and installs the mount helper before it finishes.
- First launch asks once to agree. Writable mounts of healthy external disks can turn on by default after that. Dirty or hibernated volumes stay read-only. Internal disks are skipped.
- In-app Sparkle stays off. Updates are the GitHub Release package.
- About, Settings, and the menu-bar About item show the marketing version from Info.plist.
- Package SHA256: `42d807362ca99d849b2f56eccbaaa058d939626bb548d77ba507a607885ad085` `NTFSMount.pkg`.

[1.0]: https://github.com/bio-apple/NTFSMount/releases/tag/v1.0
