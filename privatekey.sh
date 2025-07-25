#!/bin/bash
set -euo pipefail

# --- Homebrew OpenSSL 3.x path detection ---
OPENSSL_BIN="/opt/homebrew/bin/openssl"
if [[ ! -x "$OPENSSL_BIN" ]]; then
  OPENSSL_BIN="/usr/local/bin/openssl"
fi
if [[ ! -x "$OPENSSL_BIN" ]]; then
  echo "❌ Homebrew OpenSSL 3.x not found at /opt/homebrew/bin/openssl or /usr/local/bin/openssl."
  echo "   Install with: brew install openssl"
  exit 1
fi

OPENSSL_VERSION="$($OPENSSL_BIN version)"
if [[ "$OPENSSL_VERSION" == *"LibreSSL"* ]] || ! "$OPENSSL_BIN" version | grep -qE 'OpenSSL 3\.'; then
  echo "❌ Homebrew OpenSSL 3.x is required. Found: $OPENSSL_VERSION"
  exit 1
fi

# --- Check required tools ---
for cmd in xxd awk grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command not found: $cmd"
    exit 1
  fi
done

# --- BIP39 wordlist location ---
WORDLIST="./english.txt"
if [[ ! -f "$WORDLIST" ]]; then
  echo "❌ BIP39 wordlist not found at $WORDLIST"
  exit 1
fi

# --- Mnemonic input and normalization ---
echo "⚠️  WARNING: Never use this script for real funds. For educational/testing only."
echo "📥 Enter your 12/15/18/21/24-word mnemonic:"
read -r mnemonic_raw
mnemonic=$(echo "$mnemonic_raw" | tr '[:upper:]' '[:lower:]' | awk '{$1=$1;print}')

# --- Validate mnemonic ---
IFS=' ' read -r -a words <<< "$mnemonic"
word_count=${#words[@]}
declare -a valid_counts=(12 15 18 21 24)
if [[ ! " ${valid_counts[*]} " =~ " $word_count " ]]; then
  echo "❌ Invalid number of words: $word_count"
  exit 1
fi
for word in "${words[@]}"; do
  if ! grep -qx "$word" "$WORDLIST"; then
    echo "❌ Invalid BIP39 word: $word"
    exit 1
  fi
done
echo "✅ Mnemonic is valid."

# --- Optional passphrase ---
echo "🔐 Enter optional passphrase (press Enter to skip):"
read -rs passphrase
echo
salt="mnemonic$passphrase"

# --- BIP39 seed derivation (PBKDF2-HMAC-SHA512, 2048 rounds, 64 bytes) ---
if ! seed_hex=$("$OPENSSL_BIN" kdf -keylen 64 -kdfopt digest:SHA512 -kdfopt pass:"$mnemonic" -kdfopt salt:"$salt" -kdfopt iter:2048 PBKDF2 2>/dev/null | xxd -p -c 64); then
  echo "❌ Seed derivation failed. Check OpenSSL version and kdf support."
  exit 1
fi

echo
echo "🔋 BIP39 Seed (64 bytes / 512 bits):"
echo "$seed_hex"

# --- BIP32 master key derivation (HMAC-SHA512, key='Bitcoin seed') ---
seed_bin=$(echo "$seed_hex" | xxd -r -p)
master_key_hex=$(echo -n "$seed_bin" | "$OPENSSL_BIN" dgst -sha512 -mac HMAC -macopt key:"Bitcoin seed" | awk '{print $2}')

if [[ ${#master_key_hex} -ne 128 ]]; then
  echo "❌ Unexpected master key length: ${#master_key_hex} hex chars"
  exit 1
fi

privkey_hex="${master_key_hex:0:64}"
chaincode_hex="${master_key_hex:64:64}"

echo
echo "🔑 BIP32 Master Private Key (first 32 bytes):"
echo "$privkey_hex"

echo
echo "🔗 BIP32 Chain Code (next 32 bytes):"
echo "$chaincode_hex"

echo
cat <<EOF
✅ Done. You now have:
  • Validated BIP39 mnemonic
  • 512-bit seed (BIP39)
  • BIP32 master private key
  • BIP32 master chain code

⚠️  WARNING: Never use this script for real funds. For educational/testing only.
EOF
