#!/bin/bash
# 把 ntfs-3g / mkntfs / ntfsfix / go-nfsv4 / libfuse 放进 runtime/，供 build.sh 打进 app。
# FUSE-T（go-nfsv4 / libfuse）不进 Git：从官方 pkg 取得，runtime/SHA256SUMS 校验。
# ntfs-3g 四件套优先用 runtime/ 已提交的捆绑文件。仅当缺失且 Homebrew 对该 macOS
# 有 bottle 时才 brew install --force-bottle ntfs-3g。禁止 --build-from-source，
# 禁止 brew install macfuse / fuse-t。FUSE-T 钉死版本见 FUSE_T_VERSION 与 versions.txt。
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
FUSE_T_LIB_DIR="/Library/Application Support/fuse-t/lib"

die() { echo "error: $*" >&2; exit 1; }

# Homebrew：Apple Silicon 是 /opt/homebrew，Intel 旧前缀才是 /usr/local。不要只信 PATH。
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

# 优先 brew --prefix / command -v；Apple Silicon 回落到 /opt/homebrew，最后才是 /usr/local。
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

find_mount_ntfs() {
  local p
  p="$(command -v mount_ntfs 2>/dev/null || true)"
  if [[ -n "$p" && -x "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  for p in /opt/homebrew/sbin/mount_ntfs /opt/homebrew/bin/mount_ntfs /usr/local/sbin/mount_ntfs /usr/local/bin/mount_ntfs; do
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

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
  ${FUSE_T_LIB_DIR}/libfuse-t-${FUSE_T_VERSION}.dylib
  /usr/local/lib/libfuse-t-${FUSE_T_VERSION}.dylib
不使用 /usr/local/lib/libfuse.2.dylib（那是 macFUSE）。不查找 /usr/local/bin/go-nfsv4。
哈希与 SHA256SUMS 一致才用本机副本，否则改下官方 ${FUSE_T_VERSION} pkg 并解出二进制（不会把 FUSE-T 装进系统）。

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
    || [[ -n "$(find_local_fuse_t_dylib || true)" ]]
}

# FUSE-T 1.2.x 不再提供 libfuse.2.dylib（macFUSE 才装那个）。libfuse 2 ABI 在 libfuse-t-VERSION.dylib。
find_local_fuse_t_dylib() {
  local f
  for f in \
    "${FUSE_T_LIB_DIR}/libfuse-t-${FUSE_T_VERSION}.dylib" \
    "${FUSE_T_LIB_DIR}/libfuse-t.dylib" \
    "/usr/local/lib/libfuse-t-${FUSE_T_VERSION}.dylib" \
    "/usr/local/lib/libfuse-t.dylib"
  do
    if [[ -f "$f" ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

pkg_find_named() {
  local root="$1" name="$2"
  /usr/bin/find "$root" -name "$name" -type f -print -quit 2>/dev/null || true
}

check_build_deps() {
  local ver="" p="" brew_bin="" mp=""
  echo "FUSE-T 钉死 ${FUSE_T_VERSION}（runtime/versions.txt）。" >&2
  export_homebrew_path

  if brew_bin="$(find_brew)"; then
    echo "已找到 Homebrew：$brew_bin" >&2
  else
    echo "未找到 Homebrew（Apple Silicon 通常是 /opt/homebrew/bin/brew，不是 /usr/local）。" >&2
  fi
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

  if bundled_ntfs3g_present; then
    echo "已找到捆绑 ntfs-3g：$RUNTIME/ntfs-3g（不执行 brew）" >&2
  elif p="$(find_ntfs3g_bin)"; then
    echo "已找到 ntfs-3g：$p" >&2
  elif find_brew >/dev/null && brew_ntfs3g_has_macos_bottle; then
    echo "未找到 ntfs-3g。将执行：brew install --force-bottle ntfs-3g" >&2
  else
    echo "未找到捆绑 ntfs-3g，且 Homebrew 无 macOS bottle（homebrew/core 现为 Linux-only）。" >&2
  fi
  if mp="$(find_mount_ntfs)"; then
    echo "（可选）本机 mount_ntfs：$mp — 运行时不用它，只用捆绑 ntfs-3g。" >&2
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

bundled_ntfs3g_present() {
  [[ -f "$RUNTIME/ntfs-3g" && -f "$RUNTIME/mkntfs" && -f "$RUNTIME/ntfsfix" && -f "$RUNTIME/libntfs-3g.90.dylib" ]]
}

# homebrew/core 的 ntfs-3g 现为 Linux-only；仅当 JSON 里出现非 linux bottle 才允许 brew。
brew_ntfs3g_has_macos_bottle() {
  local brew_bin json
  brew_bin="$(find_brew)" || return 1
  json="$("$brew_bin" info --json=v2 ntfs-3g 2>/dev/null || true)"
  [[ -n "$json" ]] || return 1
  printf '%s' "$json" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    files = d["formulae"][0].get("bottle", {}).get("stable", {}).get("files", {})
except Exception:
    sys.exit(1)
sys.exit(0 if any(not str(k).endswith("linux") for k in files) else 1)
'
}

brew_ntfs3g_would_pull_fuse() {
  local brew_bin deps
  brew_bin="$(find_brew)" || return 1
  deps="$("$brew_bin" deps --union ntfs-3g 2>/dev/null || true)"
  if printf '%s' "$deps" | /usr/bin/grep -qiE '(^|[[:space:]])(macfuse|fuse-t|osxfuse)($|[[:space:]])'; then
    return 0
  fi
  return 1
}

copy_bundled_ntfs3g() {
  local name
  bundled_ntfs3g_present || return 1
  for name in ntfs-3g mkntfs ntfsfix libntfs-3g.90.dylib; do
    hashes_ok "$RUNTIME/$name" "$name" || return 1
  done
  copy_if_exec "$RUNTIME/ntfs-3g" "$WORK/ntfs-3g" || return 1
  copy_if_exec "$RUNTIME/mkntfs" "$WORK/mkntfs" || return 1
  copy_if_exec "$RUNTIME/ntfsfix" "$WORK/ntfsfix" || return 1
  copy_if_exec "$RUNTIME/libntfs-3g.90.dylib" "$WORK/libntfs-3g.90.dylib" || return 1
  assert_arm64 "$WORK/ntfs-3g"
  assert_arm64 "$WORK/mkntfs"
  assert_arm64 "$WORK/ntfsfix"
  assert_arm64 "$WORK/libntfs-3g.90.dylib"
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
  fuse_src="$(find_local_fuse_t_dylib || true)"
  local_ver="$(local_fuse_t_version || true)"

  if [[ -n "$local_ver" && "$local_ver" != "$FUSE_T_VERSION" ]]; then
    echo "warning: 本机 FUSE-T ${local_ver} 超出钉死版本 ${FUSE_T_VERSION}，不用本机副本。" >&2
  elif [[ -f "$go_src" && -n "$fuse_src" && -f "$fuse_src" ]]; then
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
  go_src="$(pkg_find_named "$expanded" "go-nfsv4-${FUSE_T_VERSION}")"
  [[ -n "$go_src" && -f "$go_src" ]] || go_src="$(pkg_find_named "$expanded" "go-nfsv4")"
  # 1.2.x 包内是 libfuse-t-VERSION.dylib，没有 libfuse.2.dylib；复制成 libfuse.2.dylib 供 ntfs-3g @rpath。
  fuse_src="$(pkg_find_named "$expanded" "libfuse.2.dylib")"
  [[ -n "$fuse_src" && -f "$fuse_src" ]] || fuse_src="$(pkg_find_named "$expanded" "libfuse-t-${FUSE_T_VERSION}.dylib")"
  [[ -n "$fuse_src" && -f "$fuse_src" ]] || fuse_src="$(pkg_find_named "$expanded" "libfuse-t.dylib")"
  [[ -n "$go_src" && -f "$go_src" ]] || die "pkg 里没有 go-nfsv4"
  [[ -n "$fuse_src" && -f "$fuse_src" ]] || die "pkg 里没有 libfuse-t / libfuse.2.dylib"
  copy_if_exec "$go_src" "$WORK/go-nfsv4"
  copy_if_exec "$fuse_src" "$WORK/libfuse.2.dylib"
  verify_file "$WORK/go-nfsv4" go-nfsv4
  verify_file "$WORK/libfuse.2.dylib" libfuse.2.dylib
}

ntfs3g_prefix() {
  local bin real dir
  bin="$(find_ntfs3g_bin)" || return 1
  dir="$(/usr/bin/dirname "$bin")"
  if [[ -d "$dir" ]] && dir="$(cd "$dir" && /bin/pwd -P)"; then
    real="${dir}/$(/usr/bin/basename "$bin")"
  else
    real="$bin"
  fi
  if [[ "$real" == */bin/ntfs-3g ]]; then
    printf '%s' "$(/usr/bin/dirname "$(/usr/bin/dirname "$real")")"
    return 0
  fi
  printf '%s' "$(/usr/bin/dirname "$real")"
}

assert_arm64() {
  local file="$1"
  /usr/bin/file "$file" | /usr/bin/grep -q 'arm64' || die "$file 不是 arm64 Mach-O"
}

copy_beside_or() {
  local dest="$1" name="$2" prefix="$3"
  local bin dir
  bin="$(find_ntfs3g_bin)" || true
  dir=""
  [[ -n "$bin" ]] && dir="$(/usr/bin/dirname "$bin")"
  copy_if_exec "$prefix/bin/$name" "$dest" \
    || copy_if_exec "$prefix/sbin/$name" "$dest" \
    || { [[ -n "$dir" ]] && copy_if_exec "$dir/$name" "$dest"; } \
    || return 1
}

obtain_ntfs3g() {
  local prefix brew_bin bin
  export_homebrew_path
  if copy_bundled_ntfs3g; then
    echo "使用已捆绑的 runtime ntfs-3g（跳过 brew）" >&2
    return 0
  fi
  if ! prefix="$(ntfs3g_prefix)"; then
    brew_bin="$(find_brew || true)"
    if [[ -n "$brew_bin" ]] && brew_ntfs3g_has_macos_bottle && ! brew_ntfs3g_would_pull_fuse; then
      echo "brew install --force-bottle ntfs-3g" >&2
      HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1 "$brew_bin" install --force-bottle ntfs-3g
      export_homebrew_path
      prefix="$(ntfs3g_prefix)" || die "brew install --force-bottle ntfs-3g 后仍找不到 ntfs-3g"
    else
      die "未找到可用的 ntfs-3g。homebrew/core 现为 Linux-only，GitHub-hosted macOS 没有 bottle。
不要 brew install --build-from-source ntfs-3g（慢，还可能拖 macfuse）。
不要 brew install macfuse / fuse-t。
把已校验的 ntfs-3g / mkntfs / ntfsfix / libntfs-3g.90.dylib 放进 runtime/ 后重跑；
打包机仅在该 OS 有 bottle 时才：brew install --force-bottle ntfs-3g && ./scripts/prepare-runtime.sh"
    fi
  fi
  bin="$(find_ntfs3g_bin)" || die "找不到 ntfs-3g"
  copy_if_exec "$bin" "$WORK/ntfs-3g"
  copy_beside_or "$WORK/mkntfs" mkntfs "$prefix" || die "找不到 mkntfs（Homebrew ntfs-3g 通常自带）"
  copy_beside_or "$WORK/ntfsfix" ntfsfix "$prefix" || die "找不到 ntfsfix（Homebrew ntfs-3g 通常自带）"
  copy_if_exec "$prefix/lib/libntfs-3g.90.dylib" "$WORK/libntfs-3g.90.dylib" \
    || die "找不到 libntfs-3g.90.dylib（应在 $(printf '%s' "$prefix")/lib）"
  assert_arm64 "$WORK/ntfs-3g"
  assert_arm64 "$WORK/mkntfs"
  assert_arm64 "$WORK/ntfsfix"
  assert_arm64 "$WORK/libntfs-3g.90.dylib"
}

# 把当前 Mach-O 里实际链接的 libntfs-3g / libfuse 改成 @rpath（不硬编码 Homebrew 前缀）。
relink_ntfs3g_libs() {
  local bin old
  for bin in "$WORK/ntfs-3g" "$WORK/mkntfs" "$WORK/ntfsfix"; do
    [[ -x "$bin" ]] || continue
    old="$(/usr/bin/otool -L "$bin" | /usr/bin/awk '/libntfs-3g\.90\.dylib/{print $1; exit}')"
    if [[ -n "$old" && "$old" != "@rpath/libntfs-3g.90.dylib" ]]; then
      install_name_tool -change "$old" '@rpath/libntfs-3g.90.dylib' "$bin" 2>/dev/null || true
    fi
  done
  old="$(/usr/bin/otool -L "$WORK/ntfs-3g" | /usr/bin/awk '/libfuse\.2\.dylib/{print $1; exit}')"
  if [[ -n "$old" && "$old" != "@rpath/libfuse.2.dylib" ]]; then
    install_name_tool -change "$old" '@rpath/libfuse.2.dylib' "$WORK/ntfs-3g" 2>/dev/null || true
  fi
}

[[ -f "$SUMS" ]] || die "缺少 $SUMS"

# shellcheck source=ntfs3g-version.sh
. "$ROOT/scripts/ntfs3g-version.sh"

export_homebrew_path
check_build_deps
obtain_fuse_t
obtain_ntfs3g

ntfs3g_id="$(/usr/bin/otool -D "$WORK/libntfs-3g.90.dylib" | /usr/bin/awk 'NR==2 {print; exit}')"
if [[ "$ntfs3g_id" != "@rpath/libntfs-3g.90.dylib" ]]; then
  install_name_tool -id '@rpath/libntfs-3g.90.dylib' "$WORK/libntfs-3g.90.dylib"
fi
relink_ntfs3g_libs
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
ntfs3g_out="$("$RUNTIME/ntfs-3g" --version 2>&1 || true)"
echo "$ntfs3g_out"
"$RUNTIME/mkntfs" --version
"$RUNTIME/ntfsfix" --version
ntfs3g_ver="$(ntfs3g_parse_version "$ntfs3g_out")"
pin="$(/usr/bin/awk '/^ntfs-3g[[:space:]]/{print $2; exit}' "$ROOT/runtime/versions.txt" 2>/dev/null || true)"
pin="${pin:-$NTFS3G_PINNED}"
if ! ntfs3g_version_allowed "$ntfs3g_ver"; then
  cat <<EOF >&2
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
warning: 捆绑 ntfs-3g 版本 ${ntfs3g_ver:-unknown} 不在允许列表（${NTFS3G_ALLOW_HUMAN}）。
未知版本有写入风险。请改用已测试版本，或审核后更新 runtime/versions.txt 与 Ntfs3gVersion.swift。
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
EOF
fi
if [[ -n "$pin" && -n "$ntfs3g_ver" && "$ntfs3g_ver" != "$pin" ]]; then
  echo "warning: 下载到的 ntfs-3g ${ntfs3g_ver} 与 runtime/versions.txt 钉死的 ${pin} 不一致。请更新 versions.txt 后再当作新钉死版本，不要静默越过。" >&2
fi
echo "runtime ready (SHA256 verified against $SUMS):"
/bin/ls -lh "$RUNTIME/go-nfsv4" "$RUNTIME/ntfs-3g" "$RUNTIME/mkntfs" "$RUNTIME/ntfsfix" "$RUNTIME/libfuse.2.dylib" "$RUNTIME/libntfs-3g.90.dylib"
