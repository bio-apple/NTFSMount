#!/bin/bash
# prepare-runtime 之后、打包之前：按 runtime/SHA256SUMS 校验捆绑运行时。
# 哈希只来自 SHA256SUMS，不在本脚本再写一份。
# 捆绑二进制在 runtime/；FUSE-T 安装包在 runtime/.cache/。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUMS="$ROOT/runtime/SHA256SUMS"
[[ -f "$SUMS" ]] || {
  echo "error: 缺少 $SUMS" >&2
  exit 1
}

work="$(/usr/bin/mktemp -d /tmp/ntfsmount-sha256.XXXXXX)"
trap '/bin/rm -rf "$work"' EXIT

verified=0
while read -r hash name || [[ -n "${hash:-}" ]]; do
  [[ -z "${hash:-}" || "$hash" == \#* ]] && continue
  [[ -n "${name:-}" ]] || continue
  src=""
  if [[ -f "$ROOT/runtime/$name" ]]; then
    src="$ROOT/runtime/$name"
  elif [[ -f "$ROOT/runtime/.cache/$name" ]]; then
    src="$ROOT/runtime/.cache/$name"
  elif [[ "$name" == *.pkg ]]; then
    echo "skip ${name}（prepare-runtime 用了本机 FUSE-T，未留下安装包）" >&2
    continue
  else
    echo "error: SHA256SUMS 中的捆绑文件 $name 在 prepare-runtime 之后不存在" >&2
    exit 1
  fi
  /bin/ln -s "$src" "$work/$name"
  printf '%s  %s\n' "$hash" "$name" >>"$work/SHA256SUMS"
  verified=$((verified + 1))
done <"$SUMS"

if [[ "$verified" -lt 1 ]]; then
  echo "error: $SUMS 没有可校验的条目" >&2
  exit 1
fi

# 暂存目录里只有实际找到的文件；哈希仍来自 runtime/SHA256SUMS。
(cd "$work" && /usr/bin/shasum -a 256 -c SHA256SUMS)
echo "ok runtime SHA256 ($verified files, $SUMS)"
