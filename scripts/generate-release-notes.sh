#!/bin/bash
# Build structured Release notes from git log since the previous v* tag.
# Usage:
#   generate-release-notes.sh <v1.2.2|1.2.2> [-o PATH] [--since v1.2.0]
# Writes markdown to stdout, or to PATH with -o. Does not invent What’s new:
# bullets are commit subjects. Helper reinstall / config sections are always
# present; Yes is inferred from HELPER_VERSION / helperd / IPC / CDHash /
# install-helper, otherwise No with verify.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "usage: generate-release-notes.sh <vX.Y.Z|X.Y.Z> [-o PATH] [--since vX.Y.Z]" >&2
  exit 2
}

raw=""
out=""
since_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | --output)
    [[ $# -ge 2 ]] || usage
    out="$2"
    shift 2
    ;;
  --since)
    [[ $# -ge 2 ]] || usage
    since_override="$2"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "error: unknown flag $1" >&2
    usage
    ;;
  *)
    if [[ -n "$raw" ]]; then
      echo "error: extra argument $1" >&2
      usage
    fi
    raw="$1"
    shift
    ;;
  esac
done

[[ -n "$raw" ]] || usage
ver="${raw#v}"
tag="v${ver}"

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
[[ -n "$git_dir" ]] || {
  echo "error: not a git repo" >&2
  exit 1
}
if [[ -f "$git_dir/shallow" ]]; then
  echo "warning: shallow clone; notes may miss commits. CI must checkout fetch-depth: 0." >&2
fi

end_ref="HEAD"
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  end_ref="$tag"
fi

prev=""
if [[ -n "$since_override" ]]; then
  prev="$since_override"
else
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    [[ "$t" == "$tag" ]] && continue
    prev="$t"
    break
  done < <(git tag -l 'v[0-9]*' --sort=-v:refname)
fi

if [[ -n "$prev" ]]; then
  range="${prev}..${end_ref}"
  prev_sha="$(git rev-parse --short "$prev")"
else
  range="$end_ref"
fi

lower() {
  printf '%s' "$1" | /usr/bin/tr '[:upper:]' '[:lower:]'
}

skip_subject() {
  local sl
  sl="$(lower "$1")"
  [[ -z "$sl" ]] && return 0
  [[ "$sl" == "no" ]] && return 0
  [[ "$sl" == merge* ]] && return 0
  [[ "$sl" == checkpoint* ]] && return 0
  return 1
}

# Features / Fixes / Breaking / Other. Prefixes first, then keyword match for
# prose subjects (this repo often has "Fix helper…" / "Ship …" without feat:).
classify() {
  local sl
  sl="$(lower "$1")"
  case "$sl" in
  breaking* | *" breaking "* | *breaking:* | *incompatible* | *helper_version* | *"reinstall helper"*)
    printf '%s\n' breaking
    return
    ;;
  esac
  case "$sl" in
  feat:* | feat\(* | "feat "* | add:* | add\(* | "add "* | added:* | "added "* | ship:* | "ship "* | new:* | "new "*)
    printf '%s\n' feature
    return
    ;;
  esac
  case "$sl" in
  fix:* | fix\(* | "fix "* | fixed:* | "fixed "* | fixes:* | "fixes "* | bug:* | "bug "* | bugfix:* | "bugfix "*)
    printf '%s\n' fix
    return
    ;;
  esac
  case "$sl" in
  *" fix "* | *" fixed "* | *" fixes "* | *" bug "* | *" bugfix "*)
    printf '%s\n' fix
    return
    ;;
  esac
  case "$sl" in
  *" add "* | *" added "* | *" helper ipc"*)
    printf '%s\n' feature
    return
    ;;
  esac
  printf '%s\n' other
}

helper_reason=""
note_helper() {
  local item="$1"
  case "|${helper_reason}|" in
  *"|${item}|"*) return ;;
  esac
  if [[ -z "$helper_reason" ]]; then
    helper_reason="$item"
  else
    helper_reason="${helper_reason}|${item}"
  fi
}

scan_helper() {
  local sl
  sl="$(lower "$1")"
  case "$sl" in *helper_version*) note_helper "HELPER_VERSION" ;; esac
  case "$sl" in *helperd*) note_helper "helperd" ;; esac
  case "$sl" in *ipc*) note_helper "IPC" ;; esac
  case "$sl" in *cdhash*) note_helper "CDHash" ;; esac
  case "$sl" in
  *install-helper* | *"install helper"* | *"helper install"*)
    note_helper "install-helper"
    ;;
  esac
}

config_ud=0
config_automount=0
scan_config() {
  local sl
  sl="$(lower "$1")"
  case "$sl" in
  *userdefaults* | *didmigrate* | *com.bioapple.ntfsmount* | *renamed*key*)
    config_ud=1
    ;;
  esac
  case "$sl" in
  *automountuseroff* | *auto-mount* | *automount* | *launchdaemon*plist*)
    config_automount=1
    ;;
  esac
}

already_listed() {
  local needle="$1"
  local x
  [[ ${#listed[@]} -eq 0 ]] && return 1
  for x in "${listed[@]}"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

listed=()
features=()
fixes=()
breaking=()
other=()
count=0

while IFS= read -r subject; do
  skip_subject "$subject" && continue
  already_listed "$subject" && continue
  listed+=("$subject")
  scan_helper "$subject"
  scan_config "$subject"
  count=$((count + 1))
  bucket="$(classify "$subject")"
  case "$bucket" in
  feature) features+=("$subject") ;;
  fix) fixes+=("$subject") ;;
  breaking) breaking+=("$subject") ;;
  *) other+=("$subject") ;;
  esac
done < <(git log --no-merges --format='%s' "$range")

# Helper inference also looks at patch hunks: HELPER_VERSION in a subject is rare.
pickaxe_helper() {
  local needle="$1"
  local label="$2"
  local hits
  hits="$(git log --no-merges -G "$needle" --format='%H' "$range" || true)"
  if [[ -n "$hits" ]]; then
    note_helper "$label"
  fi
}
pickaxe_helper "HELPER_VERSION" "HELPER_VERSION"
pickaxe_helper "ntfsmount-helperd" "helperd"
pickaxe_helper "allowed.cdhash" "CDHash"

emit_bullets() {
  if [[ $# -eq 0 ]]; then
    printf '%s\n' "- None detected from commit messages in this range."
    return
  fi
  local line
  for line in "$@"; do
    printf -- '- %s\n' "$line"
  done
}

compared=""
if [[ -n "$prev" ]]; then
  compared="Compared to ${prev} (\`${prev_sha}\`). Generated from \`git log --no-merges ${range}\`. Do not invent What’s new."
else
  compared="No previous v* tag. Generated from \`git log --no-merges ${range}\`. Do not invent What’s new."
fi

helper_block=""
if [[ -n "$helper_reason" ]]; then
  helper_block=$(
    cat <<EOF
- **Yes.** After replacing the app, use **Update mount helper**. Required even if writable mounts still appear to work.
- Why: commit messages in this range mention ${helper_reason//|/, }.
- Verify on a machine that already has the helper installed.
EOF
  )
else
  helper_block=$(
    cat <<'EOF'
- **No** (inferred from commit messages; verify).
- Why: no HELPER_VERSION / helperd / IPC / CDHash / install-helper mentions in git log since the previous tag.
- If writable mounts fail after replacing the app, use **Update mount helper** anyway.
EOF
  )
fi

if [[ "$config_ud" -eq 1 ]]; then
  ud_line="- **UserDefaults:** Commit messages mention preference keys. Verify keys kept, renamed, or migrated."
else
  ud_line="- **UserDefaults:** No key changes detected in commit messages; existing keys should still apply. Verify."
fi
if [[ "$config_automount" -eq 1 ]]; then
  am_line="- **Auto-mount:** Commit messages mention auto-mount / LaunchDaemon. Verify \`autoMountUserOff\` and plist names."
else
  am_line="- **Auto-mount:** No auto-mount / LaunchDaemon plist changes detected in commit messages. Verify \`autoMountUserOff\` still applies."
fi
if [[ -n "$helper_reason" ]]; then
  stamp_line="- **Helper stamp:** \`helper.stamp\` / \`allowed.cdhash\` likely need rewriting (helper identity mentioned in this range). Verify after install."
else
  stamp_line="- **Helper stamp:** No helper-identity change detected in commit messages; verify \`helper.stamp\` / \`allowed.cdhash\` still match."
fi

body="$(/usr/bin/mktemp)"
{
  printf '%s\n' "# NTFSMount ${ver}"
  echo
  printf '%s\n' "Personal-use pre-release. Not notarized. Do not mirror or treat as a product until FUSE-T written permission and Apple notarization. See NOTICE."
  echo
  printf '%s\n' "Apple Silicon + macOS 13.0+ only. GitHub **pre-release** (not Latest) unless the build is notarized **and** \`FUSE_T_REDISTRIBUTION_OK=1\`."
  echo
  printf '%s\n' "$compared"
  if [[ "$count" -eq 0 ]]; then
    echo
    printf '%s\n' "No non-merge commits in this range."
  fi
  echo
  printf '%s\n\n' "## What's new"
  if [[ ${#features[@]} -eq 0 ]]; then
    emit_bullets
  else
    emit_bullets "${features[@]}"
  fi
  echo
  printf '%s\n\n' "## Fixes"
  if [[ ${#fixes[@]} -eq 0 ]]; then
    emit_bullets
  else
    emit_bullets "${fixes[@]}"
  fi
  echo
  printf '%s\n\n' "## Breaking Changes"
  if [[ ${#breaking[@]} -eq 0 ]]; then
    emit_bullets
  else
    emit_bullets "${breaking[@]}"
  fi
  echo
  printf '%s\n\n' "## Changes"
  if [[ ${#other[@]} -eq 0 ]]; then
    emit_bullets
  else
    emit_bullets "${other[@]}"
  fi
  cat <<'EOF'

## Known issues

- Unnotarized: Gatekeeper blocks first launch (Control-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Personal-use only (bundled FUSE-T). Do not mirror.
- This tag is a GitHub **pre-release** (not Latest) unless notarization and FUSE-T redistribution are both done.

## Helper: reinstall required?

EOF
  printf '%s\n' "$helper_block"
  echo
  printf '%s\n\n' "## Old config compatibility"
  printf '%s\n' "$ud_line"
  printf '%s\n' "$am_line"
  printf '%s\n' "$stamp_line"
  printf '%s\n' "- **Leftover sudoers:** \`/etc/sudoers.d/ntfs-rw\` — still deleted on install/update/uninstall. Do not keep NOPASSWD leftovers."
  cat <<'EOF'

## Verify the DMG

CI appends SHA256 after packaging. Do not invent a hash here.
EOF
} >"$body"

if [[ -n "$out" ]]; then
  out_dir="$(/usr/bin/dirname "$out")"
  [[ -d "$out_dir" ]] || /bin/mkdir -p "$out_dir"
  /bin/cp "$body" "$out"
  echo "ok $out (${count} commits, range ${range})" >&2
else
  /bin/cat "$body"
fi
/bin/rm -f "$body"
