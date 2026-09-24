# Third-party licenses

NTFSMount ships the following binaries inside `NTFSMount.app/Contents/MacOS` (filled by `scripts/prepare-runtime.sh` into `runtime/`, which is not committed). Each component remains under its upstream license.

## ntfs-3g, mkntfs, ntfsfix, libntfs-3g

- **Upstream:** Tuxera ntfs-3g
- **License:** GNU General Public License v2.0 (GPL-2.0)
- **Source:** https://github.com/tuxera/ntfs-3g

These binaries provide NTFS read/write mounting, optional dirty-volume repair (`ntfsfix`), and formatting. Because they are GPL-2.0, the combined work in this repository is offered under **GPL-2.0-or-later**. See [LICENSE](./LICENSE).

## libfuse.2.dylib

- **Upstream:** FUSE-T libfuse 2.x shim
- **License:** GNU Lesser General Public License v2.1 (LGPL-2.1)
- **Source:** https://github.com/macos-fuse-t/libfuse

Userspace FUSE library used by the bundled ntfs-3g. No kernel extension is required at runtime.

## go-nfsv4

- **Upstream:** FUSE-T
- **License:** FUSE-T NFS server (proprietary; free for personal use — embedding or shipping in a product may require a commercial license from the FUSE-T authors)
- **Source:** https://www.fuse-t.org/ · https://github.com/macos-fuse-t/fuse-t

`go-nfsv4` is the NFSv4 userspace server shipped with FUSE-T. It is not GPL. Packaged-app users do not need a system FUSE-T install; this binary is copied into the app bundle at build time.

**Personal use only until you have written permission or a commercial license from the FUSE-T authors.** Do not sell or redistribute this app as a product without that license. Pre-release GitHub downloads are not a commercial distribution grant. See [NOTICE](./NOTICE). Set `FUSE_T_REDISTRIBUTION_OK=1` when packaging only after you have it. Contact: https://www.fuse-t.org/

## Notices

This file is informational and is not legal advice. The GPL-2.0 text is in [LICENSE](./LICENSE). LGPL-2.1 is available at https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
