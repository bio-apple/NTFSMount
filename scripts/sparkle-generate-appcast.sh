#!/bin/bash
# Build Sparkle appcast.xml from dist/NTFSMount.pkg using generate_appcast.
# Enclosure URL points at a GitHub Release asset (default pre-release v1.2.0), not Latest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.10.0}"
TAG="${SPARKLE_RELEASE_TAG:-v1.2.0}"
PREFIX="${SPARKLE_DOWNLOAD_PREFIX:-https://github.com/bio-apple/NTFSMount/releases/download/${TAG}/}"
KEYFILE="${SPARKLE_ED_KEY_FILE:-$HOME/Library/Application Support/NTFSMount-sparkle/eddsa-private.key}"
PKG="${1:-$ROOT/dist/NTFSMount.pkg}"
OUT="${SPARKLE_APPCAST_OUT:-$ROOT/dist/appcast.xml}"
CACHE="$ROOT/.build/sparkle-tools/$SPARKLE_VERSION"

if [[ ! -f "$PKG" ]]; then
  echo "error: missing $PKG — run ./scripts/package-pkg.sh first" >&2
  exit 1
fi
if [[ ! -f "$KEYFILE" ]]; then
  echo "error: missing Sparkle private key at $KEYFILE" >&2
  echo "Run ./scripts/sparkle-generate-keys.sh first (key stays outside git)." >&2
  exit 1
fi

find_generate_appcast() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "$SPARKLE_BIN/generate_appcast"
    return 0
  fi
  local cand
  cand="$(/usr/bin/find "$ROOT/.build/artifacts" -name generate_appcast -type f -print -quit 2>/dev/null || true)"
  if [[ -n "$cand" && -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  if [[ -x "$CACHE/bin/generate_appcast" ]]; then
    echo "$CACHE/bin/generate_appcast"
    return 0
  fi
  return 1
}

ensure_generate_appcast() {
  local tool
  if tool="$(find_generate_appcast)"; then
    echo "$tool"
    return 0
  fi
  echo "==> downloading Sparkle $SPARKLE_VERSION tools (generate_appcast)" >&2
  mkdir -p "$CACHE"
  local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  local archive="$CACHE/Sparkle-${SPARKLE_VERSION}.tar.xz"
  if [[ ! -f "$archive" ]]; then
    /usr/bin/curl -fsSL "$url" -o "$archive"
  fi
  /usr/bin/tar -xJf "$archive" -C "$CACHE" --strip-components=0
  # Archive layout varies: bin/ at top or Sparkle-*/bin
  tool="$(/usr/bin/find "$CACHE" -name generate_appcast -type f -print -quit || true)"
  if [[ -z "$tool" ]]; then
    echo "error: generate_appcast not found after extracting Sparkle tools" >&2
    exit 1
  fi
  /usr/bin/xattr -dr com.apple.quarantine "$CACHE" 2>/dev/null || true
  chmod +x "$tool"
  if [[ ! -x "$tool" ]]; then
    echo "error: generate_appcast is not executable: $tool" >&2
    exit 1
  fi
  echo "$tool"
}

TOOL="$(ensure_generate_appcast)"
STAGE="$(/usr/bin/mktemp -d /tmp/ntfsmount-appcast.XXXXXX)"
cleanup() { /bin/rm -rf "$STAGE"; }
trap cleanup EXIT

/bin/cp "$PKG" "$STAGE/NTFSMount.pkg"

echo "==> generate_appcast (EdDSA; enclosure prefix $PREFIX)"
# --ed-key-file: 32-byte seed, base64 (openssl / sparkle-generate-keys.sh).
# Do not pass the key on the command line as a value.
"$TOOL" --ed-key-file "$KEYFILE" --download-url-prefix "$PREFIX" "$STAGE"

if [[ ! -f "$STAGE/appcast.xml" ]]; then
  echo "error: generate_appcast did not write $STAGE/appcast.xml" >&2
  /bin/ls -la "$STAGE" >&2
  exit 1
fi

mkdir -p "$(/usr/bin/dirname "$OUT")"
/bin/cp "$STAGE/appcast.xml" "$OUT"
echo "wrote $OUT"
echo "Publish as a GitHub Release asset (not Latest):"
echo "  gh release upload $TAG --clobber $OUT"
echo "SUFeedURL is $PREFIX""appcast.xml"
echo "See docs/SPARKLE.md."
