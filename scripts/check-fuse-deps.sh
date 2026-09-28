#!/bin/bash
# 一键检查 Homebrew / ntfs-3g / FUSE-T。推荐用户态 FUSE-T（NFS/WebDAV），不装 kext、不关 SIP。
# 用法:
#   ./scripts/check-fuse-deps.sh           # 只检查
#   ./scripts/check-fuse-deps.sh --install # 缺 ntfs-3g 时 brew install ntfs-3g；不装 macFUSE
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount 仅支持 Apple Silicon（M 芯片 / arm64），不支持 Intel Mac（x86_64）。当前架构：$(/usr/bin/uname -m)" >&2
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
用法: $0 [--install]

检查本机构建/运行 NTFSMount 所需依赖。推荐 FUSE-T（用户态 NFS/WebDAV），无需关闭 SIP。

  （默认）     只检查，缺件时退出码 1
  --install    缺 ntfs-3g 时执行 brew install ntfs-3g
               不安装 macFUSE / osxfuse 内核扩展
               FUSE-T 请用 ./scripts/prepare-runtime.sh（官方 pkg，钉死 ${FUSE_T_VERSION}）

不要:
  brew install macfuse     # kext；macOS 11+ / Apple Silicon 常需降低 SIP
  brew install fuse-t      # 本仓库钉死官方 pkg ${FUSE_T_VERSION}，不用 Homebrew 配方
EOF
}

die() { echo "error: $*" >&2; exit 1; }

ok() { echo "ok    $*"; }
warn() { echo "warn  $*"; WARN=1; }
bad() { echo "fail  $*"; FAIL=1; }

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --install)
      INSTALL=1
      ;;
    --install-macfuse|macfuse)
      die "本项目不安装 macFUSE / osxfuse 内核扩展，也不要求降低 SIP。请用 FUSE-T：./scripts/prepare-runtime.sh"
      ;;
    *)
      die "未知参数: $arg（见 --help）"
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
    *) PATH="$dir:$PATH"; export PATH ;;
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
    /usr/local/bin/ntfs-3g
  do
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
  "$brew_bin" list --formula macfuse >/dev/null 2>&1 \
    || "$brew_bin" list --cask macfuse >/dev/null 2>&1
}

echo "NTFSMount 依赖检查（Apple Silicon / 用户态 FUSE-T，无需关闭 SIP）"
echo "钉死 FUSE-T ${FUSE_T_VERSION}（runtime/versions.txt）。应用捆绑 go-nfsv4，不加载 kext。"
echo

export_homebrew_path

# --- Homebrew ---
BREW=""
if BREW="$(find_brew)"; then
  ok "Homebrew  $BREW"
else
  bad "未找到 Homebrew。Apple Silicon 通常是 /opt/homebrew/bin/brew。
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# --- ntfs-3g（唯一允许的 brew install）---
NTFS3G=""
if NTFS3G="$(find_ntfs3g_bin)"; then
  ok "ntfs-3g   $NTFS3G"
elif [[ "$INSTALL" -eq 1 ]]; then
  if [[ -z "$BREW" ]]; then
    bad "无法 brew install ntfs-3g：没有 Homebrew"
  else
    echo "run   $BREW install ntfs-3g"
    "$BREW" install ntfs-3g
    export_homebrew_path
    if NTFS3G="$(find_ntfs3g_bin)"; then
      ok "ntfs-3g   $NTFS3G（刚安装）"
    else
      bad "brew install ntfs-3g 后仍找不到 ntfs-3g"
    fi
  fi
else
  if [[ -n "$BREW" ]]; then
    bad "未找到 ntfs-3g。请执行：$BREW install ntfs-3g
  或一次性：$0 --install"
  else
    bad "未找到 ntfs-3g，且没有 Homebrew"
  fi
fi

# --- FUSE-T（官方 pkg / 捆绑；不用 brew install fuse-t）---
FUSE_OK=0
if [[ -x "$RUNTIME/go-nfsv4" ]]; then
  ok "FUSE-T    仓库 runtime/go-nfsv4（prepare-runtime 已取出）"
  FUSE_OK=1
fi
if [[ -x "${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}" || -x "${FUSE_T_BIN_DIR}/go-nfsv4" ]]; then
  ok "FUSE-T    本机 ${FUSE_T_BIN_DIR}（可选；打包时会校验 SHA256）"
  FUSE_OK=1
elif [[ -d /Applications/FUSE-T.app ]]; then
  warn "本机有 FUSE-T.app，但未找到 ${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}。运行时用捆绑副本，不必启动 FUSE-T.app。"
fi
if [[ "$FUSE_OK" -eq 0 ]]; then
  warn "未找到 runtime/go-nfsv4 或本机 FUSE-T ${FUSE_T_VERSION}。构建前请运行：
  ./scripts/prepare-runtime.sh
  （下载官方 pkg，不把 FUSE-T 静默装进系统；不要 brew install fuse-t）"
fi

# --- 弃用 kext ---
if kext_macfuse_present; then
  warn "检测到 macFUSE / osxfuse 内核扩展。本应用不使用 kext，可能干扰 FUSE-T。不要为了本应用关闭 SIP。"
elif brew_macfuse_listed; then
  warn "Homebrew 列出了 macfuse。本应用不需要它。不要 brew install macfuse，不要降低 SIP。"
fi

echo
echo "推荐路径：FUSE-T（NFS/WebDAV 用户态）+ Homebrew ntfs-3g。"
echo "不要 brew install macfuse（kext）。不要 brew install fuse-t（本仓库用官方 pkg）。"
echo "不必关闭 SIP，也不必允许内核扩展。"

if [[ "$FAIL" -ne 0 ]]; then
  echo
  echo "检查未通过。补齐 ntfs-3g 后可再跑 $0；取 FUSE-T 二进制请用 ./scripts/prepare-runtime.sh"
  exit 1
fi
if [[ "$WARN" -ne 0 && "$FUSE_OK" -eq 0 ]]; then
  echo
  echo "检查有告警。最终构建仍须 ./scripts/prepare-runtime.sh"
  exit 1
fi
echo
echo "ok check-fuse-deps"
exit 0
