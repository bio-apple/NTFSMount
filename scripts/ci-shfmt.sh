#!/bin/bash
# CI / 本机：检查仓库内 bash 的 shfmt 缩进（含无 .sh 后缀的 helper）。
# 用法: ./scripts/ci-shfmt.sh
# 修正: shfmt -w -i 2 <files>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() {
  echo "error: $*" >&2
  exit 1
}

SHFMT="$(command -v shfmt || true)"
if [[ -z "$SHFMT" ]]; then
  die "shfmt not found. CI installs it; locally: brew install shfmt"
fi

# 与 scripts/ci-shellcheck.sh 同一文件列表。不要扫 .build / runtime。
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(
  {
    printf '%s\n' uninstall.sh helper/ntfs-rw-helper scripts/ntfsmount
    /usr/bin/find helper scripts -type f -name '*.sh' -print
  } | /usr/bin/awk 'NF && !seen[$0]++' | /usr/bin/sort
)

[[ ${#files[@]} -gt 0 ]] || die "no scripts to check"
for f in "${files[@]}"; do
  [[ -f "$f" ]] || die "missing $f"
done

echo "shfmt -d -i 2 (${#files[@]} files):"
printf '  %s\n' "${files[@]}"

"$SHFMT" -d -i 2 -- "${files[@]}"
echo "ok shfmt"
