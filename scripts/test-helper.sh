#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/helper/ntfs-rw-helper"
[[ "$(/usr/bin/head -1 "$HELPER")" == "#!/bin/bash" ]] || { echo "ntfs-rw-helper must be in-repo bash source" >&2; exit 1; }
echo "helper sha256=$(/usr/bin/shasum -a 256 "$HELPER" | /usr/bin/awk '{print $1}')"

PRIV_SCAN=()
for f in "$ROOT"/helper/*.sh "$ROOT"/helper/ntfs-rw-helper "$ROOT"/scripts/*.sh "$ROOT"/uninstall.sh; do
  [[ -f "$f" ]] || continue
  [[ "${f##*/}" == "test-helper.sh" ]] && continue
  PRIV_SCAN+=("$f")
done
if /usr/bin/grep -nE 'ALL=\(root\) NOPASSWD' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not write sudoers NOPASSWD" >&2
  exit 1
fi
if /usr/bin/grep -nE 'sudo[[:space:]]+-S\b|SUDO_ASKPASS|[[:space:]]ASKPASS=|^ASKPASS=' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not feed sudo from stdin or set an ask-pass helper" >&2
  exit 1
fi
if /usr/bin/grep -nE 'echo[[:space:]].*\|[[:space:]]*sudo|printf[[:space:]].*\|[[:space:]]*sudo' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not pipe a secret into sudo" >&2
  exit 1
fi
# Literal password assignments only. Do not match NSAppleEventsUsageDescription or env names like APPLE_CERTIFICATE_PASSWORD.
if /usr/bin/grep -nE '(password|passwd|PASSWORD)[[:space:]]*=[[:space:]]*["'\''][^"'\'']+["'\'']' "${PRIV_SCAN[@]}" 2>/dev/null; then
  echo "scripts must not hardcode passwords" >&2
  exit 1
fi
if /usr/bin/grep -nE 'osascript|/usr/bin/sudo|[[:space:]]sudo[[:space:]]' "$ROOT"/Sources/NTFSMount/VolumeStore.swift 2>/dev/null; then
  echo "mount/unmount/format must go through the helper daemon, not sudo/osascript" >&2
  exit 1
fi
if /usr/bin/grep -n 'ln -sf' "$ROOT/helper/install-helper.sh"; then
  echo "install-helper must not recreate /usr/local/sbin symlink" >&2
  exit 1
fi

# 命令位不得出现未加引号的 /Volumes/$name（"My Passport" 会切成两个 argv）
if /usr/bin/grep -nE '(^|[^"=$])/Volumes/\$name' "$HELPER"; then
  echo "helper contains unquoted /Volumes/\$name" >&2
  exit 1
fi

out="$("$HELPER" selftest)"
echo "$out"
[[ "$out" == ok\ selftest* ]] || { echo "selftest failed" >&2; exit 1; }
ver="$("$HELPER" version)"
[[ "$ver" == HELPER_VERSION=6 ]] || { echo "version mismatch: $ver" >&2; exit 1; }

# shellcheck disable=SC2016 # literal $(whoami) payload the helper must reject
for bad in 'disk12s1;whoami' 'disk 12s1' '../disk1s1' 'disk5s1$(whoami)' 'disk4;id' 'mount'; do
  if "$HELPER" mount "$bad" >/dev/null 2>&1; then
    echo "should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" format "$bad" >/dev/null 2>&1; then
    echo "format should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" fix "$bad" >/dev/null 2>&1; then
    echo "fix should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" ntfsfix "$bad" >/dev/null 2>&1; then
    echo "ntfsfix should reject: $bad" >&2
    exit 1
  fi
  if "$HELPER" eject "$bad" >/dev/null 2>&1; then
    echo "eject should reject: $bad" >&2
    exit 1
  fi
done

# 带空格路径必须作为单一 argv（不真正挂载/格式化）
quote_tmp="$(/usr/bin/mktemp -d /tmp/ntfsmount-space.XXXXXX)"
space_mp="${quote_tmp}/My Passport"
/bin/mkdir -p "$space_mp"
[[ -d "$space_mp" ]] || { echo "quoted mkdir with spaces failed: $space_mp" >&2; exit 1; }
/bin/rm -rf "$quote_tmp"

# format 必须在 mkntfs / eraseDisk 之前拒绝系统盘与 APFS 物理卷。不真正抹盘。
root_plist="$(/usr/sbin/diskutil info -plist / 2>/dev/null || true)"
sys="$(printf '%s' "$root_plist" | /usr/bin/plutil -extract ParentWholeDisk raw - 2>/dev/null || true)"
store="$(printf '%s' "$root_plist" | /usr/bin/plutil -extract APFSPhysicalStores.0.APFSPhysicalStore raw - 2>/dev/null || true)"
refuse_ids=()
if [[ -n "$sys" && "$sys" != "null" ]]; then
  refuse_ids+=("$sys")
  refuse_ids+=("${sys%%s*}")
fi
if [[ -n "$store" && "$store" != "null" ]]; then
  refuse_ids+=("$store")
  refuse_ids+=("${store%%s*}")
fi
[[ ${#refuse_ids[@]} -gt 0 ]] || { echo "cannot identify system disk for format-refusal test" >&2; exit 1; }
seen_refuse=
for ident in "${refuse_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+$ ]] || continue
  fmt_err="$("$HELPER" format "$ident" 2>&1 || true)"
  if printf '%s' "$fmt_err" | /usr/bin/grep -q 'ok formatted'; then
    echo "format must never succeed on system disk $ident: $fmt_err" >&2
    exit 1
  fi
  if printf '%s' "$fmt_err" | /usr/bin/grep -q '拒绝格式化'; then
    seen_refuse=1
  else
    echo "format should refuse system/internal disk $ident: $fmt_err" >&2
    exit 1
  fi
done
[[ -n "$seen_refuse" ]] || { echo "format did not refuse any system/internal whole disk" >&2; exit 1; }

# fix/ntfsfix 必须在真正 ntfsfix 之前拒绝系统盘与 APFS 物理卷。不真正修用户盘。
fix_ids=()
if [[ -n "$store" && "$store" != "null" && "$store" =~ ^disk[0-9]+s[0-9]+$ ]]; then
  fix_ids+=("$store")
fi
for ident in "${refuse_ids[@]}"; do
  if [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]]; then
    fix_ids+=("$ident")
  elif [[ "$ident" =~ ^disk[0-9]+$ ]]; then
    fix_ids+=("${ident}s1")
  fi
done
[[ ${#fix_ids[@]} -gt 0 ]] || { echo "cannot identify system partition for fix-refusal test" >&2; exit 1; }
seen_fix_refuse=
for ident in "${fix_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]] || continue
  fix_err="$("$HELPER" fix "$ident" 2>&1 || true)"
  if printf '%s' "$fix_err" | /usr/bin/grep -q 'ok fixed'; then
    echo "fix must never succeed on system disk $ident: $fix_err" >&2
    exit 1
  fi
  if printf '%s' "$fix_err" | /usr/bin/grep -q 'ok formatted'; then
    echo "fix must never format $ident: $fix_err" >&2
    exit 1
  fi
  if printf '%s' "$fix_err" | /usr/bin/grep -q '拒绝修复'; then
    seen_fix_refuse=1
  fi
  alias_err="$("$HELPER" ntfsfix "$ident" 2>&1 || true)"
  if printf '%s' "$alias_err" | /usr/bin/grep -q 'ok fixed'; then
    echo "ntfsfix must never succeed on system disk $ident: $alias_err" >&2
    exit 1
  fi
done
[[ -n "$seen_fix_refuse" ]] || { echo "fix did not refuse any system/internal disk" >&2; exit 1; }

# eject：非法 id 已在上面拒绝。系统盘/内置分区不得成功推出（不真正 eject 用户外置盘）。
seen_eject_refuse=
for ident in "${fix_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+s[0-9]+$ ]] || continue
  ej_err="$("$HELPER" eject "$ident" 2>&1 || true)"
  if printf '%s' "$ej_err" | /usr/bin/grep -q 'ok ejected'; then
    echo "eject must never succeed on system disk $ident: $ej_err" >&2
    exit 1
  fi
  if printf '%s' "$ej_err" | /usr/bin/grep -q '拒绝推出'; then
    seen_eject_refuse=1
  fi
done
for ident in "${refuse_ids[@]}"; do
  [[ "$ident" =~ ^disk[0-9]+$ ]] || continue
  ej_err="$("$HELPER" eject "$ident" 2>&1 || true)"
  if printf '%s' "$ej_err" | /usr/bin/grep -q 'ok ejected'; then
    echo "eject must never succeed on system whole disk $ident: $ej_err" >&2
    exit 1
  fi
done
[[ -n "$seen_eject_refuse" ]] || { echo "eject did not refuse any system/internal partition" >&2; exit 1; }

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
[[ -f "$ROOT/runtime/SHA256SUMS" ]]
[[ -f "$ROOT/runtime/versions.txt" ]]
if /usr/bin/git -C "$ROOT" ls-files --error-unmatch runtime/go-nfsv4 >/dev/null 2>&1; then
  echo "runtime/go-nfsv4 must not be tracked in git" >&2
  exit 1
fi

export MACOSX_DEPLOYMENT_TARGET=13.0
swift test --package-path "$ROOT"

echo "ok tests"
