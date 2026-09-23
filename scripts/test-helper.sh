#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/helper/ntfs-rw-helper"
[[ "$(/usr/bin/head -1 "$HELPER")" == "#!/bin/bash" ]] || { echo "ntfs-rw-helper must be in-repo bash source" >&2; exit 1; }
echo "helper sha256=$(/usr/bin/shasum -a 256 "$HELPER" | /usr/bin/awk '{print $1}')"

if /usr/bin/grep -nE 'ALL=\(root\) NOPASSWD' "$ROOT"/helper/*.sh "$ROOT"/scripts/*.sh "$ROOT"/uninstall.sh 2>/dev/null; then
  echo "scripts must not write sudoers NOPASSWD" >&2
  exit 1
fi
if /usr/bin/grep -n 'ln -sf' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must not recreate /usr/local/sbin symlink" >&2
  exit 1
fi

out="$("$HELPER" selftest)"
echo "$out"
[[ "$out" == ok\ selftest* ]] || { echo "selftest failed" >&2; exit 1; }
ver="$("$HELPER" version)"
[[ "$ver" == HELPER_VERSION=5 ]] || { echo "version mismatch: $ver" >&2; exit 1; }

# shellcheck disable=SC2016 # literal $(whoami) payload the helper must reject
for bad in 'disk12s1;whoami' 'disk 12s1' '../disk1s1' 'disk5s1$(whoami)' 'disk4;id'; do
  if "$HELPER" mount "$bad" >/dev/null 2>&1; then
    echo "should reject: $bad" >&2
    exit 1
  fi
done

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TMPD="$(/usr/bin/mktemp -d /tmp/ntfsmount-helperd.XXXXXX)"
clang -O2 -arch arm64 -mmacosx-version-min=13.0 -isysroot "$SDK" \
  -framework Security -framework CoreFoundation \
  -o "$TMPD/helperd" "$ROOT/helper/ntfsmount-helperd.c"
file "$TMPD/helperd" | /usr/bin/grep -q 'arm64' || { echo "helperd not arm64" >&2; exit 1; }
/bin/rm -rf "$TMPD"

# README 与界面不得再写「没有程序坞」或「点盘名即可挂载」
if /usr/bin/grep -n '没有程序坞图标' "$ROOT/README.md"; then
  echo "README still says no Dock icon" >&2
  exit 1
fi
if /usr/bin/grep -n '点盘名即可' "$ROOT/README.md"; then
  echo "README still says click the disk name" >&2
  exit 1
fi
[[ -f "$ROOT/Resources/NTFSMount.entitlements" ]]
[[ -f "$ROOT/helper/com.bioapple.ntfsmount.helper.plist" ]]
[[ -f "$ROOT/docs/DISTRIBUTION.md" ]]
[[ -f "$ROOT/NOTICE" ]]
[[ -f "$ROOT/docs/MANUAL_TEST.md" ]]

export MACOSX_DEPLOYMENT_TARGET=13.0
swift test --package-path "$ROOT"

echo "ok tests"
