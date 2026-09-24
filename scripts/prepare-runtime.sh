#!/bin/bash
# 把 ntfs-3g / mkntfs / ntfsfix / go-nfsv4 / libfuse 放进 runtime/，供 build.sh 打进 app。
# 二进制不进 Git：从 FUSE-T 官方 pkg 与 Homebrew ntfs-3g 取得，并用 runtime/SHA256SUMS 校验。
# FUSE-T 钉死版本见 FUSE_T_VERSION 与 runtime/versions.txt（Package.swift 无法钉 macOS pkg）。
set -euo pipefail
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" != "1" && "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "error: NTFSMount 仅支持 Apple Silicon（M 芯片 / arm64），不支持 Intel Mac（x86_64）。当前架构：$(/usr/bin/uname -m)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$ROOT/runtime"
SUMS="$RUNTIME/SHA256SUMS"
CACHE="$RUNTIME/.cache"
WORK="$(/usr/bin/mktemp -d /tmp/ntfsmount-prep.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$RUNTIME" "$CACHE"

# 已知可用：FUSE-T 1.2.7。换大版本时同步本常量、runtime/versions.txt、runtime/SHA256SUMS。
FUSE_T_VERSION="1.2.7"
FUSE_T_PKG_NAME="fuse-t-macos-installer-${FUSE_T_VERSION}.pkg"
FUSE_T_URL="${FUSE_T_PKG_URL:-https://github.com/macos-fuse-t/fuse-t/releases/download/${FUSE_T_VERSION}/${FUSE_T_PKG_NAME}}"
FUSE_T_BIN_DIR="/Library/Application Support/fuse-t/bin"
FUSE_T_LIBFUSE="/usr/local/lib/libfuse.2.dylib"

die() { echo "error: $*" >&2; exit 1; }

print_fuse_t_install_help() {
  local pkg_sha=""
  if [[ -f "$SUMS" ]]; then
    pkg_sha="$(/usr/bin/awk -v n="$FUSE_T_PKG_NAME" '$1 !~ /^#/ && NF>=2 && $2==n {print $1; exit}' "$SUMS")"
  fi
  cat <<EOF >&2
FUSE-T 不是 GPL，通常不在 Homebrew。不要 brew install fuse-t（专有软件；未获书面许可不可当产品再分发）。

钉死版本：FUSE-T ${FUSE_T_VERSION}（与 runtime/versions.txt、runtime/SHA256SUMS 一致）
官方 pkg（GitHub release，不是 Homebrew）：
  ${FUSE_T_URL}
安装到本机（可选；本脚本不会静默安装 FUSE-T）：
  curl -fL -o /tmp/${FUSE_T_PKG_NAME} '${FUSE_T_URL}'
  shasum -a 256 /tmp/${FUSE_T_PKG_NAME}   # 期望 ${pkg_sha:-见 runtime/SHA256SUMS}
  open /tmp/${FUSE_T_PKG_NAME}

本脚本查找本机文件（pkg 安装后即出现，不必先启动 FUSE-T.app）：
  ${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}
  ${FUSE_T_BIN_DIR}/go-nfsv4
  ${FUSE_T_LIBFUSE}
不查找 /usr/local/bin/go-nfsv4。哈希与 SHA256SUMS 一致才用本机副本，否则改下官方 ${FUSE_T_VERSION} pkg 并解出二进制（不会把 FUSE-T 装进系统）。

不必启动 FUSE-T.app，也不必加载系统 FUSE-T 守护进程：prepare-runtime 只复制文件；NTFSMount 运行时用包内捆绑的 go-nfsv4（FUSE_NFSSRV_PATH），不依赖系统级 FUSE-T。

未取得 FUSE-T 书面许可前仅供个人使用预发布，禁止当公开产品再分发。见 NOTICE。
EOF
}

# 读出版本：优先 go-nfsv4-x.y.z 文件名，其次 FUSE-T.app Info.plist。对不上 1.2.7 则拒绝本机副本。
local_fuse_t_version() {
  local f base ver
  if [[ -x "${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}" ]]; then
    printf '%s' "$FUSE_T_VERSION"
    return 0
  fi
  for f in "${FUSE_T_BIN_DIR}"/go-nfsv4-*; do
    [[ -e "$f" ]] || continue
    base="$(/usr/bin/basename "$f")"
    ver="${base#go-nfsv4-}"
    if [[ "$ver" != "$base" && -n "$ver" ]]; then
      printf '%s' "$ver"
      return 0
    fi
  done
  if [[ -f /Applications/FUSE-T.app/Contents/Info.plist ]]; then
    ver="$(/usr/bin/defaults read /Applications/FUSE-T.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)"
    if [[ -n "$ver" ]]; then
      printf '%s' "$ver"
      return 0
    fi
  fi
  return 1
}

local_fuse_t_present() {
  [[ -x "${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}" ]] \
    || [[ -x "${FUSE_T_BIN_DIR}/go-nfsv4" ]] \
    || [[ -f "$FUSE_T_LIBFUSE" ]]
}

check_build_deps() {
  echo "FUSE-T 钉死 ${FUSE_T_VERSION}（runtime/versions.txt）。" >&2

  if command -v brew >/dev/null 2>&1; then
    echo "已找到 Homebrew：$(command -v brew)" >&2
  else
    echo "未找到 Homebrew（Apple Silicon 通常是 /opt/homebrew/bin/brew）。" >&2
  fi

  local ver="" p=""
  if local_fuse_t_present; then
    ver="$(local_fuse_t_version || true)"
    if [[ -z "$ver" ]]; then
      echo "本机有 FUSE-T 文件，但读不出版本；哈希须等于 SHA256SUMS 中的 ${FUSE_T_VERSION}，否则改下官方 pkg。" >&2
    elif [[ "$ver" != "$FUSE_T_VERSION" ]]; then
      echo "warning: 本机 FUSE-T ${ver} 不是钉死的 ${FUSE_T_VERSION}，拒绝使用本机副本。" >&2
      print_fuse_t_install_help
    else
      echo "本机 FUSE-T ${ver}。哈希一致则复制，不必启动 FUSE-T.app。" >&2
    fi
  else
    echo "未找到本机 FUSE-T ${FUSE_T_VERSION}（${FUSE_T_BIN_DIR}）。将下载官方 pkg 解出 go-nfsv4 / libfuse，不会把 FUSE-T 装进系统。" >&2
    print_fuse_t_install_help
  fi

  if p="$(ntfs3g_prefix)"; then
    echo "已找到 ntfs-3g：$p" >&2
  elif command -v brew >/dev/null 2>&1; then
    echo "未找到 ntfs-3g。将执行：brew install ntfs-3g" >&2
  else
    die "未找到 Homebrew，也无法定位 ntfs-3g。请先安装 Homebrew 再装 ntfs-3g：
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
  brew install ntfs-3g
然后重新运行 ./scripts/prepare-runtime.sh"
  fi
}

expected_sha() {
  local name="$1" line
  line="$(/usr/bin/awk -v n="$name" '$1 !~ /^#/ && NF>=2 && $2==n {print $1; exit}' "$SUMS")"
  [[ -n "$line" ]] || die "runtime/SHA256SUMS 没有 $name"
  printf '%s' "$line"
}

verify_file() {
  local file="$1" name="$2" want have
  [[ -f "$file" ]] || die "找不到 $file"
  want="$(expected_sha "$name")"
  have="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  if [[ "$have" != "$want" ]]; then
    die "SHA256 不符：$name
  得到 $have
  期望 $want
请确认来源版本，或在审核后更新 runtime/SHA256SUMS。"
  fi
}

hashes_ok() {
  local file="$1" name="$2" want have
  [[ -f "$file" ]] || return 1
  want="$(expected_sha "$name")"
  have="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  [[ "$have" == "$want" ]]
}

fetch_url() {
  local url="$1" dest="$2" dir
  dir="$(/usr/bin/dirname "$dest")"
  echo "download $url" >&2
  if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    (cd "$dir" && gh release download "$FUSE_T_VERSION" --repo macos-fuse-t/fuse-t --pattern "$FUSE_T_PKG_NAME" --clobber) \
      && [[ -f "$dest" ]] && return 0
  fi
  /usr/bin/curl --http1.1 -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$dest" "$url"
}

copy_if_exec() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || return 1
  /bin/cp "$src" "$dest"
  /bin/chmod 755 "$dest"
}

obtain_fuse_t() {
  local go_src fuse_src pkg expanded local_ver=""
  go_src="${FUSE_T_BIN_DIR}/go-nfsv4-${FUSE_T_VERSION}"
  [[ -x "$go_src" ]] || go_src="${FUSE_T_BIN_DIR}/go-nfsv4"
  fuse_src="$FUSE_T_LIBFUSE"
  local_ver="$(local_fuse_t_version || true)"

  if [[ -n "$local_ver" && "$local_ver" != "$FUSE_T_VERSION" ]]; then
    echo "warning: 本机 FUSE-T ${local_ver} 超出钉死版本 ${FUSE_T_VERSION}，不用本机副本。" >&2
  elif [[ -f "$go_src" && -f "$fuse_src" ]]; then
    copy_if_exec "$go_src" "$WORK/go-nfsv4"
    copy_if_exec "$fuse_src" "$WORK/libfuse.2.dylib"
    if hashes_ok "$WORK/go-nfsv4" go-nfsv4 && hashes_ok "$WORK/libfuse.2.dylib" libfuse.2.dylib; then
      return 0
    fi
    echo "本机 FUSE-T 与 SHA256SUMS 不符（需要 ${FUSE_T_VERSION}），改下官方 pkg" >&2
  fi

  pkg="$CACHE/$FUSE_T_PKG_NAME"
  if [[ -f "$pkg" ]] && ! hashes_ok "$pkg" "$FUSE_T_PKG_NAME"; then
    /bin/rm -f "$pkg"
  fi
  if [[ ! -f "$pkg" ]]; then
    fetch_url "$FUSE_T_URL" "$pkg"
  fi
  verify_file "$pkg" "$FUSE_T_PKG_NAME"

  expanded="$WORK/fuse-t-pkg"
  /usr/sbin/pkgutil --expand-full "$pkg" "$expanded"
  go_src="$(/usr/bin/find "$expanded" \( -name "go-nfsv4-${FUSE_T_VERSION}" -o -name 'go-nfsv4' \) -type f -print -quit)"
  fuse_src="$(/usr/bin/find "$expanded" -name 'libfuse.2.dylib' -type f -print -quit)"
  [[ -n "$go_src" && -f "$go_src" ]] || die "pkg 里没有 go-nfsv4"
  [[ -n "$fuse_src" && -f "$fuse_src" ]] || die "pkg 里没有 libfuse.2.dylib"
  copy_if_exec "$go_src" "$WORK/go-nfsv4"
  copy_if_exec "$fuse_src" "$WORK/libfuse.2.dylib"
  verify_file "$WORK/go-nfsv4" go-nfsv4
  verify_file "$WORK/libfuse.2.dylib" libfuse.2.dylib
}

ntfs3g_prefix() {
  local p
  if command -v brew >/dev/null 2>&1; then
    p="$(brew --prefix ntfs-3g 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p/bin/ntfs-3g" ]]; then
      printf '%s' "$p"
      return 0
    fi
  fi
  if [[ -x /opt/homebrew/opt/ntfs-3g/bin/ntfs-3g ]]; then
    printf '%s' /opt/homebrew/opt/ntfs-3g
    return 0
  fi
  if [[ -x /usr/local/bin/ntfs-3g ]]; then
    printf '%s' /usr/local
    return 0
  fi
  return 1
}

assert_arm64() {
  local file="$1"
  /usr/bin/file "$file" | /usr/bin/grep -q 'arm64' || die "$file 不是 arm64 Mach-O"
}

obtain_ntfs3g() {
  local prefix
  if ! prefix="$(ntfs3g_prefix)"; then
    if command -v brew >/dev/null 2>&1; then
      echo "brew install ntfs-3g" >&2
      brew install ntfs-3g
      prefix="$(brew --prefix ntfs-3g)"
    else
      die "需要 Homebrew ntfs-3g。请先安装 Homebrew，再执行：
  brew install ntfs-3g
Homebrew：
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
  fi
  if [[ -x "$prefix/bin/ntfs-3g" ]]; then
    copy_if_exec "$prefix/bin/ntfs-3g" "$WORK/ntfs-3g"
    copy_if_exec "$prefix/sbin/mkntfs" "$WORK/mkntfs" || copy_if_exec "$prefix/bin/mkntfs" "$WORK/mkntfs"
    copy_if_exec "$prefix/bin/ntfsfix" "$WORK/ntfsfix" \
      || copy_if_exec "$prefix/sbin/ntfsfix" "$WORK/ntfsfix" \
      || copy_if_exec /usr/local/bin/ntfsfix "$WORK/ntfsfix" \
      || copy_if_exec /usr/local/sbin/ntfsfix "$WORK/ntfsfix" \
      || die "找不到 ntfsfix（Homebrew ntfs-3g 通常自带）"
    copy_if_exec "$prefix/lib/libntfs-3g.90.dylib" "$WORK/libntfs-3g.90.dylib"
  else
    copy_if_exec /usr/local/bin/ntfs-3g "$WORK/ntfs-3g"
    copy_if_exec /usr/local/sbin/mkntfs "$WORK/mkntfs"
    copy_if_exec /usr/local/bin/ntfsfix "$WORK/ntfsfix" || copy_if_exec /usr/local/sbin/ntfsfix "$WORK/ntfsfix" \
      || die "找不到 ntfsfix（Homebrew ntfs-3g 通常自带）"
    copy_if_exec /usr/local/lib/libntfs-3g.90.dylib "$WORK/libntfs-3g.90.dylib"
  fi
  assert_arm64 "$WORK/ntfs-3g"
  assert_arm64 "$WORK/mkntfs"
  assert_arm64 "$WORK/ntfsfix"
  assert_arm64 "$WORK/libntfs-3g.90.dylib"
}

[[ -f "$SUMS" ]] || die "缺少 $SUMS"

check_build_deps
obtain_fuse_t
obtain_ntfs3g

install_name_tool -id '@rpath/libntfs-3g.90.dylib' "$WORK/libntfs-3g.90.dylib"
install_name_tool -change /usr/local/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
install_name_tool -change /opt/homebrew/opt/ntfs-3g/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
install_name_tool -change /usr/local/lib/libfuse.2.dylib '@rpath/libfuse.2.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
install_name_tool -change /usr/local/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/mkntfs" 2>/dev/null || true
install_name_tool -change /opt/homebrew/opt/ntfs-3g/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/mkntfs" 2>/dev/null || true
install_name_tool -change /usr/local/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/ntfsfix" 2>/dev/null || true
install_name_tool -change /opt/homebrew/opt/ntfs-3g/lib/libntfs-3g.90.dylib '@rpath/libntfs-3g.90.dylib' "$WORK/ntfsfix" 2>/dev/null || true
if ! /usr/bin/otool -l "$WORK/ntfs-3g" | /usr/bin/grep -q 'path @executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$WORK/ntfs-3g"
fi
if ! /usr/bin/otool -l "$WORK/mkntfs" | /usr/bin/grep -q 'path @executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$WORK/mkntfs"
fi
if ! /usr/bin/otool -l "$WORK/ntfsfix" | /usr/bin/grep -q 'path @executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$WORK/ntfsfix"
fi

/bin/cp -f "$WORK/go-nfsv4" "$WORK/libfuse.2.dylib" "$WORK/ntfs-3g" "$WORK/mkntfs" "$WORK/ntfsfix" "$WORK/libntfs-3g.90.dylib" "$RUNTIME/"
/bin/chmod 755 "$RUNTIME/go-nfsv4" "$RUNTIME/libfuse.2.dylib" "$RUNTIME/ntfs-3g" "$RUNTIME/mkntfs" "$RUNTIME/ntfsfix" "$RUNTIME/libntfs-3g.90.dylib"
"$RUNTIME/ntfs-3g" --version
"$RUNTIME/mkntfs" --version
"$RUNTIME/ntfsfix" --version
echo "runtime ready (SHA256 verified against $SUMS):"
/bin/ls -lh "$RUNTIME/go-nfsv4" "$RUNTIME/ntfs-3g" "$RUNTIME/mkntfs" "$RUNTIME/ntfsfix" "$RUNTIME/libfuse.2.dylib" "$RUNTIME/libntfs-3g.90.dylib"
