#!/bin/bash
# pkgbuild postinstall. The installer runs this as root after NTFSMount.app is copied.
# $1 package path, $2 destination, $3 target volume, $4 system root.
set -euo pipefail

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "error: package postinstall must run as root" >&2
  exit 1
fi

dest="${2:-/Applications}"
vol="${3:-/}"
case "$dest" in
  /*) ;;
  *) dest="/${dest}" ;;
esac
if [[ "$vol" == "/" ]]; then
  app="${dest}/NTFSMount.app"
else
  app="${vol%/}${dest}/NTFSMount.app"
fi

helper="${app}/Contents/Resources/ntfs-rw-helper"
helperd="${app}/Contents/MacOS/ntfsmount-helperd"
script="${app}/Contents/Resources/install-helper.sh"
user_name="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
if [[ -z "${user_name}" || "${user_name}" == "root" ]]; then
  user_name="root"
fi

[[ -d "$app" && -f "$script" && -f "$helper" && -f "$helperd" ]] || {
  echo "error: installed app is incomplete: $app" >&2
  exit 1
}

# ruid is already 0 here, so the install script keeps root without a second prompt.
/bin/bash "$script" "$helper" "$helperd" "$user_name" "$app"
