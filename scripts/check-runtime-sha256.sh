#!/bin/bash
# prepare-runtime 之后、打包之前：按 runtime/SHA256SUMS 校验捆绑运行时。
# 哈希只来自 SHA256SUMS，不在本脚本再写一份。
# 捆绑二进制在 runtime/；FUSE-T 安装包在 runtime/.cache/。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUMS="$ROOT/runtime/SHA256SUMS"
[[ -f "$SUMS" ]] || {
  echo "error: missing $SUMS" >&2
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
    echo "skip ${name} (prepare-runtime used a local FUSE-T and left no installer package)" >&2
    continue
  else
    echo "error: bundled file $name from SHA256SUMS is missing after prepare-runtime" >&2
    exit 1
  fi
  /bin/ln -s "$src" "$work/$name"
  printf '%s  %s\n' "$hash" "$name" >>"$work/SHA256SUMS"
  verified=$((verified + 1))
done <"$SUMS"

if [[ "$verified" -lt 1 ]]; then
  echo "error: $SUMS has no entries to verify" >&2
  exit 1
fi

# 暂存目录里只有实际找到的文件；哈希仍来自 runtime/SHA256SUMS。
(cd "$work" && /usr/bin/shasum -a 256 -c SHA256SUMS)
echo "ok runtime SHA256 ($verified files, $SUMS)"
