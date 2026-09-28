#!/bin/bash
# docs/MANUAL_TEST.md 的可脚本化子集。无 GUI、不公证、不抹盘、不静默清 hiberfile。
# 无 NTFS 卷时立刻失败，不空等插盘。
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount supports Apple Silicon (M-series / arm64) only, not Intel Macs (x86_64). This machine: $(/usr/bin/uname -m)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="/var/run/com.bioapple.ntfsmount.sock"
SUDOERS="/etc/sudoers.d/ntfs-rw"

echo "==> macOS $(/usr/bin/sw_vers -productVersion)  arch=$(/usr/bin/uname -m)"
echo
echo "==> docs/MANUAL_TEST.md (manual checkboxes in that file still decide)"
/bin/cat "$ROOT/docs/MANUAL_TEST.md"
echo

echo "==> diskutil list"
/usr/sbin/diskutil list
echo

echo "==> NTFS volumes (diskutil info FilesystemName=NTFS)"
found=0
while IFS= read -r ident; do
  [[ "$ident" == disk* ]] || continue
  fs="$(/usr/sbin/diskutil info -plist "$ident" 2>/dev/null | /usr/bin/plutil -extract FilesystemName raw - 2>/dev/null || true)"
  [[ "$fs" == "NTFS" ]] || continue
  found=1
  echo "---- $ident ----"
  /usr/sbin/diskutil info "$ident" | /usr/bin/grep -E 'Device Identifier:|Volume Name:|Mount Point:|File System Personality:|Protocol:|Internal:|Removable Media:' || true
done < <(/usr/sbin/diskutil list | /usr/bin/awk '/Windows_NTFS/ && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF; next } /^[[:space:]]+[0-9]+:/ && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }' | /usr/bin/awk 'NF && !seen[$0]++')

if [[ "$found" -eq 0 ]]; then
  echo "error: this machine has no NTFS volume. A GitHub-hosted runner cannot plug in USB." >&2
  echo "Plug in an external NTFS volume on a self-hosted Apple Silicon runner, then run .github/workflows/manual-disk-test.yml again." >&2
  exit 1
fi

echo
echo "==> /sbin/mount (ntfs-3g / FUSE lines)"
/sbin/mount | /usr/bin/grep -iE 'ntfs-3g|fuse-t|fuset|macfuse|osxfuse| nfs,' || echo "(no FUSE/ntfs-3g mount lines)"

echo
echo "==> in-repo helper selftest / version (not via the privileged daemon; does not mount)"
"$ROOT/helper/ntfs-rw-helper" selftest
"$ROOT/helper/ntfs-rw-helper" version

echo
echo "==> helper ping (socket / LaunchDaemon / no sudoers)"
if [[ -e "$SUDOERS" ]]; then
  echo "error: $SUDOERS must not exist (this project does not write sudoers NOPASSWD)" >&2
  exit 1
fi
echo "gone or absent: $SUDOERS"

if [[ -S "$SOCK" || -e "$SOCK" ]]; then
  echo "helper socket present: $SOCK"
  ls -l "$SOCK"
else
  echo "error: $SOCK is missing. On the runner, open NTFSMount and choose Install… to install the mount helper, then run this workflow again. CI does not show a GUI or ask for an admin password." >&2
  exit 1
fi
for p in \
  /Library/LaunchDaemons/com.bioapple.ntfsmount.helper.plist \
  /Library/PrivilegedHelperTools/com.bioapple.ntfsmount.helperd; do
  if [[ -e "$p" ]]; then
    echo "present: $p"
  else
    echo "missing: $p"
  fi
done

echo
echo "==> These MANUAL_TEST.md steps cannot be completed safely in headless CI and must be checked by hand:"
cat <<'EOF'
- Gatekeeper / not notarized: Control-click to open, System Settings → Privacy & Security → Open Anyway, then clear quarantine with xattr
- First-run confirm (Return to agree / Esc to quit) and the main window Install… banner
- Writable after insert, menu-bar Writable, Finder copy
- Eject (safe to unplug), wait until Finder drops the volume, then unplug
- System NTFS read-only, then switch to writable from the submenu
- Dirty or hibernated volumes stay read-only; pre-mount health check (dirty/corrupt dialog defaults to read-only; ntfsfix needs another confirm; hibernated volumes get no ntfsfix). Do not silently clear hiberfile or run repairVolume
- Internal / Boot Camp is not automounted; format dialog (erases the disk; CI does not run it)
- Settings → Uninstall Helper, then bash scripts/check-helper-gone.sh
- Upgrade a machine that still has the old sudoers file
EOF
echo "ok scriptable manual-disk-test"
