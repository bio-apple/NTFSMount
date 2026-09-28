#!/bin/bash
# CI / 本机：对仓库内 bash 做 ShellCheck（含无 .sh 后缀的 helper）。
# 用法: ./scripts/ci-shellcheck.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() {
  echo "error: $*" >&2
  exit 1
}

SHELLCHECK="$(command -v shellcheck || true)"
if [[ -z "$SHELLCHECK" ]]; then
  die "shellcheck not found. CI installs it; locally: brew install shellcheck"
fi

# 显式列出无后缀脚本，其余按 *.sh。不要扫 .build / runtime。
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

echo "shellcheck ${#files[@]} files:"
printf '  %s\n' "${files[@]}"

# warning 及以上失败；info/style 不拦 CI。bash 脚本统一 --shell=bash。
"$SHELLCHECK" --severity=warning --shell=bash --external-sources "${files[@]}"
echo "ok shellcheck"
