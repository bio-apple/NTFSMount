#!/bin/bash
# 一键检查 Homebrew / ntfs-3g / FUSE-T。推荐用户态 FUSE-T（NFS/WebDAV），不装 kext、不关 SIP。
# 用法:
#   ./scripts/check-fuse-deps.sh           # 只检查
#   ./scripts/check-fuse-deps.sh --install # 缺 ntfs-3g 时 brew install ntfs-3g；不装 macFUSE
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount supports Apple Silicon (M-series / arm64) only, not Intel Macs (x86_64). This machine: $(/usr/bin/uname -m)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$ROOT/runtime"
FUSE_T_VERSION="1.2.7"
if [[ -f "$RUNTIME/versions.txt" ]]; then
  FUSE_T_VERSION="$(/usr/bin/awk '/^FUSE-T[[:space:]]/{print $2; exit}' "$RUNTIME/versions.txt")"
  FUSE_T_VERSION="${FUSE_T_VERSION:-1.2.7}"
fi
FUSE_T_BIN_DIR="/Library/Application Support/fuse-t/bin"
INSTALL=0
FAIL=0
WARN=0

usage() {
  cat <<EOF
usage: $0 [--install]

Check dependencies for building and running NTFSMount. Prefer FUSE-T (userspace NFS/WebDAV). SIP stays enabled.

  (default)    check only; exit 1 when something required is missing
  --install    run brew install ntfs-3g when ntfs-3g is missing
               does not install the macFUSE / osxfuse kernel extension
               for FUSE-T, use ./scripts/prepare-runtime.sh (official pkg, pinned ${FUSE_T_VERSION})

Do not:
  brew install macfuse     # kext; this project does not use it. SIP stays enabled
  brew install fuse-t      # this repo pins official pkg ${FUSE_T_VERSION}, not a Homebrew formula
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

ok() { echo "ok    $*"; }
warn() {
  echo "warn  $*"
  WARN=1
}
bad() {
  echo "fail  $*"
  FAIL=1
}

for arg in "$@"; do
  case "$arg" in
  -h | --help)
    usage
    exit 0
    ;;
  --install)
    INSTALL=1
    ;;
  --install-macfuse | macfuse)
    die "This project does not install the macFUSE / osxfuse kernel extension. SIP stays enabled. Use FUSE-T: ./scripts/prepare-runtime.sh"
    ;;
  *)
    die "unknown argument: $arg (see --help)"
    ;;
  esac
done

find_brew() {
  local b
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 1
}

export_homebrew_path() {
  local brew_bin dir
  brew_bin="$(find_brew)" || return 0
  dir="$(/usr/bin/dirname "$brew_bin")"
  case ":$PATH:" in
  *":$dir:"*) ;;
  *)
    PATH="$dir:$PATH"
    export PATH
    ;;
  esac
}

find_ntfs3g_bin() {
  local brew_bin prefix p
  if brew_bin="$(find_brew)"; then
    prefix="$("$brew_bin" --prefix ntfs-3g 2>/dev/null || true)"
    if [[ -n "$prefix" && -x "$prefix/bin/ntfs-3g" ]]; then
      printf '%s' "$prefix/bin/ntfs-3g"
      return 0
    fi
  fi
  p="$(command -v ntfs-3g 2>/dev/null || true)"
  if [[ -n "$p" && -x "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  for p in \
    /opt/homebrew/bin/ntfs-3g \
    /opt/homebrew/opt/ntfs-3g/bin/ntfs-3g \
    /usr/local/opt/ntfs-3g/bin/ntfs-3g \
    /usr/local/bin/ntfs-3g; do
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

kext_macfuse_present() {
  local text=""
  if [[ -x /usr/sbin/kextstat ]]; then
    text="$(/usr/sbin/kextstat 2>/dev/null || true)"
    if printf '%s' "$text" | /usr/bin/grep -qiE 'macfuse|osxfuse'; then
      return 0
    fi
  fi
  if [[ -x /usr/bin/systemextensionsctl ]]; then
    text="$(/usr/bin/systemextensionsctl list 2>/dev/null || true)"
    if printf '%s' "$text" | /usr/bin/grep -qiE 'macfuse|osxfuse'; then
      return 0
    fi
  fi
  return 1
}

brew_macfuse_listed() {
  local brew_bin
  brew_bin="$(find_brew)" || return 1
  "$brew_bin" list --formula macfuse >/dev/null 2>&1 ||
    "$brew_bin" list --cask macfuse >/dev/null 2>&1
}

echo "NTFSMount dependency check (Apple Silicon / userspace FUSE-T, SIP stays enabled)"
echo "Pinned FUSE-T ${FUSE_T_VERSION} (runtime/versions.txt). The app bundles go-nfsv4 and does not load a kext."
echo

export_homebrew_path

# --- Homebrew ---
BREW=""
if BREW="$(find_brew)"; then
  ok "Homebrew  $BREW"
else
  bad "Homebrew not found. On Apple Silicon it is usually /opt/homebrew/bin/brew.
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# --- ntfs-3g（唯一允许的 brew install）---
NTFS3G=""
if NTFS3G="$(find_ntfs3g_bin)"; then
  ok "ntfs-3g   $NTFS3G"
elif [[ "$INSTALL" -eq 1 ]]; then
  if [[ -z "$BREW" ]]; then
    bad "cannot brew install ntfs-3g: Homebrew is missing"
  else
    echo "run   $BREW install ntfs-3g"
    "$BREW" install ntfs-3g
    export_homebrew_path
    if NTFS3G="$(find_ntfs3g_bin)"; then
      ok "ntfs-3g   $NTFS3G (just installed)"
    else
      bad "ntfs-3g still not found after brew install ntfs-3g"
    fi
  fi
else
  if [[ -n "$BREW" ]]; then
    bad "ntfs-3g not found. Run: $BREW install ntfs-3g
  or once: $0 --install"
  else
    bad "ntfs-3g not found, and Homebrew is missing"
  fi
fi

# --- FUSE-T（官方 pkg / 捆绑；不用 brew install fuse-t）---
FUSE_OK=0
if [[ -x "$RUNTIME/go-nfsv4" ]]; then
  ok "FUSE-T    repo runtime/go-nfsv4 (extracted by prepare-runtime)"
  FUSE_OK=1
fi
if [[ -x "${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}" || -x "${FUSE_T_BIN_DIR}/go-nfsv4" ]]; then
  ok "FUSE-T    local ${FUSE_T_BIN_DIR} (optional; packaging checks SHA256)"
  FUSE_OK=1
elif [[ -d /Applications/FUSE-T.app ]]; then
  warn "FUSE-T.app is installed, but ${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION} was not found. Runtime uses the bundled copy; you do not need to launch FUSE-T.app."
fi
if [[ "$FUSE_OK" -eq 0 ]]; then
  warn "runtime/go-nfsv4 or local FUSE-T ${FUSE_T_VERSION} was not found. Before building, run:
  ./scripts/prepare-runtime.sh
  (downloads the official pkg and does not silently install FUSE-T system-wide; do not brew install fuse-t)"
fi

# --- 弃用 kext ---
if kext_macfuse_present; then
  warn "macFUSE / osxfuse kernel extension detected. This app does not use a kext, and it may interfere with FUSE-T. SIP must stay enabled."
elif brew_macfuse_listed; then
  warn "Homebrew lists macfuse. This app does not need it. Do not brew install macfuse. SIP stays enabled."
fi

echo
echo "Preferred path: FUSE-T (userspace NFS/WebDAV) plus Homebrew ntfs-3g."
echo "Do not brew install macfuse (kext). Do not brew install fuse-t (this repo uses the official pkg)."
echo "Do not turn SIP off, and do not allow a kernel extension."

if [[ "$FAIL" -ne 0 ]]; then
  echo
  echo "Check failed. Install ntfs-3g and run $0 again. For the FUSE-T binary, use ./scripts/prepare-runtime.sh"
  exit 1
fi
if [[ "$WARN" -ne 0 && "$FUSE_OK" -eq 0 ]]; then
  echo
  echo "Check finished with warnings. The final build still needs ./scripts/prepare-runtime.sh"
  exit 1
fi
echo
echo "ok check-fuse-deps"
exit 0
