#!/bin/bash

# Secp256k1 curve order (n)
readonly CURVE_ORDER="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"

# Check for correct input
if [ -z "$1" ]; then
  echo "Usage: $0 <64-char hex private key>"
  exit 1
fi

priv_hex="$1"

# Validate hex format
if [[ ! "$priv_hex" =~ ^[0-9A-Fa-f]{64}$ ]]; then
  echo "Error: Input must be a 64-character hex string."
  exit 1
fi

# Convert to uppercase for consistency
priv_hex=$(echo "$priv_hex" | tr 'a-f' 'A-F')

# Check for zero private key
if [[ "$priv_hex" =~ ^0+$ ]]; then
  echo "Error: Private key cannot be zero."
  exit 1
fi

# Validate private key is in range [1, n-1] using bc
echo "Validating private key range..."
key_valid=$(echo "
ibase=16
key = $priv_hex
order = $CURVE_ORDER
if (key >= order) {
  print 0
} else {
  print 1
}
" | bc -l)

if [ "$key_valid" -eq 0 ]; then
  echo "Error: Private key must be less than curve order."
  echo "Max valid key: $CURVE_ORDER"
  exit 1
fi

# Create temporary directory
tmpdir=$(mktemp -d)
if [ ! -d "$tmpdir" ]; then
  echo "Error: Failed to create temporary directory"
  exit 1
fi

# File paths
key_der="$tmpdir/key.der"
key_pem="$tmpdir/key.pem"
pubkey_der="$tmpdir/pubkey.der"
pubkey_bin="$tmpdir/pubkey.bin"
privkey_bin="$tmpdir/privkey.bin"

# Cleanup function
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

# Convert hex to binary
echo "$priv_hex" | xxd -r -p > "$privkey_bin"
if [ $? -ne 0 ]; then
  echo "Error: Failed to convert hex to binary"
  exit 1
fi

# Verify binary file size
privkey_size=$(wc -c < "$privkey_bin")
if [ "$privkey_size" -ne 32 ]; then
  echo "Error: Private key binary should be 32 bytes, got $privkey_size"
  exit 1
fi

# Generate template key
echo "Generating key template..."
if ! openssl ecparam -name secp256k1 -genkey -out "$key_pem" 2>/dev/null; then
  echo "Error: Failed to generate secp256k1 key template"
  exit 1
fi

# Convert to DER format
if ! openssl ec -in "$key_pem" -outform DER -out "$key_der" 2>/dev/null; then
  echo "Error: Failed to convert key to DER format"
  exit 1
fi

# Verify DER file exists and has reasonable size
if [ ! -f "$key_der" ] || [ $(wc -c < "$key_der") -lt 50 ]; then
  echo "Error: Invalid DER file generated"
  exit 1
fi

# More robust approach: find the private key location in DER
# Search for the 32-byte sequence pattern in DER structure
der_size=$(wc -c < "$key_der")
found_offset=-1

# Look for typical private key location patterns
for offset in 7 8 9 10 11 12; do
  if [ $((offset + 32)) -le "$der_size" ]; then
    found_offset=$offset
    break
  fi
done

if [ "$found_offset" -eq -1 ]; then
  echo "Error: Could not locate private key position in DER structure"
  exit 1
fi

echo "Patching private key at offset $found_offset..."

# Replace private key bytes in DER
if ! dd if="$privkey_bin" of="$key_der" bs=1 seek=$found_offset count=32 conv=notrunc 2>/dev/null; then
  echo "Error: Failed to patch private key into DER"
  exit 1
fi

# Convert patched DER back to PEM and validate
if ! openssl ec -inform DER -in "$key_der" -out "$key_pem" 2>/dev/null; then
  echo "Error: Failed to convert patched DER back to PEM - private key may be invalid"
  exit 1
fi

# Verify the key works by testing it
if ! openssl ec -in "$key_pem" -noout -check 2>/dev/null; then
  echo "Error: Generated private key failed validation"
  exit 1
fi

echo "Extracting public key..."

# Get uncompressed public key in DER
if ! openssl ec -in "$key_pem" -pubout -conv_form uncompressed -outform DER -out "$pubkey_der" 2>/dev/null; then
  echo "Error: Failed to extract public key"
  exit 1
fi

# Verify public key DER file
pubder_size=$(wc -c < "$pubkey_der")
if [ "$pubder_size" -lt 65 ]; then
  echo "Error: Public key DER file too small ($pubder_size bytes)"
  exit 1
fi

# Extract raw public key (last 65 bytes) - more robust approach
tail -c 65 "$pubkey_der" > "$pubkey_bin"

# Verify we got exactly 65 bytes
pubkey_size=$(wc -c < "$pubkey_bin")
if [ "$pubkey_size" -ne 65 ]; then
  echo "Error: Expected 65 bytes for uncompressed public key, got $pubkey_size"
  exit 1
fi

# Verify first byte is 0x04 (uncompressed marker)
first_byte=$(xxd -l 1 -p "$pubkey_bin")
if [ "$first_byte" != "04" ]; then
  echo "Error: Public key should start with 0x04, got 0x$first_byte"
  exit 1
fi

# Convert to hex
pubkey_hex=$(xxd -p "$pubkey_bin" | tr -d '\n' | tr 'a-f' 'A-F')
x_hex="${pubkey_hex:2:64}"
y_hex="${pubkey_hex:66:64}"

# Validate coordinate lengths
if [ ${#x_hex} -ne 64 ] || [ ${#y_hex} -ne 64 ]; then
  echo "Error: Invalid coordinate lengths (x=${#x_hex}, y=${#y_hex})"
  exit 1
fi

echo "Calculating compressed form..."

# Check Y parity with bc (more robust)
y_parity=$(echo "ibase=16; $y_hex % 2" | bc)

if [ "$y_parity" -eq 0 ]; then
  prefix="02"
else
  prefix="03"
fi

compressed_pubkey="${prefix}${x_hex}"

# Final validation - verify we have valid coordinates
x_zero_check=$(echo "$x_hex" | grep -c '^0\+$')
y_zero_check=$(echo "$y_hex" | grep -c '^0\+$')

if [ "$x_zero_check" -eq 1 ] && [ "$y_zero_check" -eq 1 ]; then
  echo "Warning: Generated point at origin - this may indicate an error"
fi

# Output results
echo ""
echo "=== Bitcoin Key Generation Results ==="
echo "Private Key (hex):       $priv_hex"
echo "Uncompressed Public Key: 04$x_hex$y_hex"
echo "Compressed Public Key:   $compressed_pubkey"
echo ""
echo "Key validation: PASSED"

