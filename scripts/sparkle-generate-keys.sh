#!/bin/bash
# Generate a Sparkle EdDSA keypair for NTFSMount updates.
# Private key stays outside git. This script never prints the secret.
set -euo pipefail

KEYDIR="${NTFSMOUNT_SPARKLE_KEYDIR:-$HOME/Library/Application Support/NTFSMount-sparkle}"
PRIV="$KEYDIR/eddsa-private.key"
PUB="$KEYDIR/eddsa-public.key"

mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR" 2>/dev/null || true

if [[ -f "$PRIV" ]]; then
  if [[ ! -f "$PUB" ]]; then
    echo "error: private key exists but $PUB is missing. Do not regenerate; recover the public key with Sparkle generate_keys or keep the existing Info.plist SUPublicEDKey." >&2
    echo "private key path (not contents): $PRIV" >&2
    exit 1
  fi
  echo "Using existing keypair (not rotated)."
  echo "SUPublicEDKey=$(/usr/bin/tr -d '[:space:]' <"$PUB")"
  echo "private key path (not contents): $PRIV"
  exit 0
fi

TMPPEM="$(/usr/bin/mktemp -t ntfsmount-ed25519)"
cleanup() { /bin/rm -f "$TMPPEM"; }
trap cleanup EXIT

/usr/bin/openssl genpkey -algorithm ED25519 -out "$TMPPEM"
SEED_B64="$(/usr/bin/openssl pkey -in "$TMPPEM" -outform DER | /usr/bin/tail -c 32 | /usr/bin/openssl base64 -A)"
PUB_B64="$(/usr/bin/openssl pkey -in "$TMPPEM" -pubout -outform DER | /usr/bin/tail -c 32 | /usr/bin/openssl base64 -A)"

umask 077
printf '%s\n' "$SEED_B64" >"$PRIV"
chmod 600 "$PRIV"
printf '%s\n' "$PUB_B64" >"$PUB"
chmod 644 "$PUB"

echo "Generated new Ed25519 keypair (Sparkle seed format, 32 bytes)."
echo "SUPublicEDKey=$PUB_B64"
echo "Put that value in Resources/Info.plist as SUPublicEDKey."
echo "private key path (not contents): $PRIV"
echo "Never commit the private key. See docs/SPARKLE.md."
