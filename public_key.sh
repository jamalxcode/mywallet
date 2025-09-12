#!/bin/bash

set -euo pipefail

# Secp256k1 curve order (n)
readonly CURVE_ORDER="FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"

# Parse options
QUIET=0
VERBOSE=0
OUTPUT_FORMAT="both"  # both, compressed, uncompressed
while getopts "qvf:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        f) OUTPUT_FORMAT="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: public_key.sh [-q] [-v] [-f format] [private_key_hex]
       echo 'private_key_hex' | public_key.sh [-q] [-v] [-f format]

Generates Bitcoin public key from secp256k1 private key.

Options:
  -q    Quiet mode (suppress warnings)
  -v    Verbose mode (show processing steps)
  -f    Output format: both, compressed, uncompressed (default: both)
  -h    Show this help

Output format:
  both:         <compressed_pubkey_hex>
                <uncompressed_pubkey_hex>
  compressed:   <compressed_pubkey_hex>  
  uncompressed: <uncompressed_pubkey_hex>

Examples:
  echo 'a1b2c3d4...' | public_key.sh -q -f compressed
  public_key.sh -v a1b2c3d4e5f678901234567890123456a1b2c3d4e5f678901234567890123456
EOF
            exit 0
            ;;
        *) exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Logging functions
warn() { [[ $QUIET -eq 0 ]] && echo "Warning: $*" >&2; }
info() { [[ $VERBOSE -eq 1 ]] && echo "Info: $*" >&2; }
die() { echo "Error: $*" >&2; exit 1; }

# Validate output format
case "$OUTPUT_FORMAT" in
    both|compressed|uncompressed) ;;
    *) die "Invalid output format: $OUTPUT_FORMAT (use: both, compressed, uncompressed)" ;;
esac

# Read and validate private key
read_private_key() {
    local priv_hex
    # Try argument first, then stdin
    if [[ $# -gt 0 ]]; then
        priv_hex="$1"
    else
        read -r priv_hex
    fi
    
    # Remove whitespace and validate format
    priv_hex=$(echo "$priv_hex" | tr -d '[:space:]')
    [[ -z "$priv_hex" ]] && die "No private key provided"
    
    if [[ ! "$priv_hex" =~ ^[0-9A-Fa-f]{64}$ ]]; then
        die "Private key must be 64 hex characters. Got: ${#priv_hex} chars"
    fi
    
    # Convert to uppercase for consistency
    priv_hex=$(echo "$priv_hex" | tr 'a-f' 'A-F')
    
    # Check for zero private key
    if [[ "$priv_hex" =~ ^0+$ ]]; then
        die "Private key cannot be zero"
    fi
    
    info "Private key validation passed"
    echo "$priv_hex"
}

# Validate private key is in valid range
validate_key_range() {
    local priv_hex="$1"
    
    info "Validating private key range against secp256k1 curve order"
    local key_valid
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
        die "Private key must be less than curve order. Max: $CURVE_ORDER"
    fi
    
    info "Private key is within valid range"
}

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in openssl xxd bc; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && die "Missing required commands: ${missing[*]}"
}

# Generate public key from private key
generate_public_key() {
    local priv_hex="$1"
    
    # Create secure temporary directory
    local tmpdir
    tmpdir=$(mktemp -d -m 700)
    [[ ! -d "$tmpdir" ]] && die "Failed to create temporary directory"
    
    # File paths
    local key_der="$tmpdir/key.der"
    local key_pem="$tmpdir/key.pem" 
    local pubkey_der="$tmpdir/pubkey.der"
    local pubkey_bin="$tmpdir/pubkey.bin"
    local privkey_bin="$tmpdir/privkey.bin"
    
    # Cleanup function
    local cleanup_done=0
    cleanup() {
        [[ $cleanup_done -eq 0 ]] && rm -rf "$tmpdir" && cleanup_done=1
    }
    trap cleanup EXIT INT TERM

    info "Converting private key to binary format"
    # Convert hex to binary
    if ! echo "$priv_hex" | xxd -r -p > "$privkey_bin"; then
        cleanup
        die "Failed to convert hex to binary"
    fi

    # Verify binary file size
    local privkey_size
    privkey_size=$(wc -c < "$privkey_bin")
    if [ "$privkey_size" -ne 32 ]; then
        cleanup
        die "Private key binary should be 32 bytes, got $privkey_size"
    fi

    info "Generating secp256k1 key template"
    # Generate template key
    if ! openssl ecparam -name secp256k1 -genkey -out "$key_pem" 2>/dev/null; then
        cleanup
        die "Failed to generate secp256k1 key template"
    fi

    # Convert to DER format
    if ! openssl ec -in "$key_pem" -outform DER -out "$key_der" 2>/dev/null; then
        cleanup
        die "Failed to convert key to DER format"
    fi

    # Verify DER file exists and has reasonable size
    if [ ! -f "$key_der" ] || [ $(wc -c < "$key_der") -lt 50 ]; then
        cleanup
        die "Invalid DER file generated"
    fi

    info "Patching private key into DER structure"
    # Find the private key location in DER structure
    local der_size found_offset=-1
    der_size=$(wc -c < "$key_der")

    # Look for typical private key location patterns
    for offset in 7 8 9 10 11 12; do
        if [ $((offset + 32)) -le "$der_size" ]; then
            found_offset=$offset
            break
        fi
    done

    if [ "$found_offset" -eq -1 ]; then
        cleanup
        die "Could not locate private key position in DER structure"
    fi

    # Replace private key bytes in DER
    if ! dd if="$privkey_bin" of="$key_der" bs=1 seek=$found_offset count=32 conv=notrunc 2>/dev/null; then
        cleanup
        die "Failed to patch private key into DER"
    fi

    # Convert patched DER back to PEM and validate
    if ! openssl ec -inform DER -in "$key_der" -out "$key_pem" 2>/dev/null; then
        cleanup
        die "Failed to convert patched DER back to PEM - private key may be invalid"
    fi

    # Verify the key works by testing it
    if ! openssl ec -in "$key_pem" -noout -check 2>/dev/null; then
        cleanup
        die "Generated private key failed validation"
    fi

    info "Extracting public key coordinates"
    # Get uncompressed public key in DER
    if ! openssl ec -in "$key_pem" -pubout -conv_form uncompressed -outform DER -out "$pubkey_der" 2>/dev/null; then
        cleanup
        die "Failed to extract public key"
    fi

    # Verify public key DER file
    local pubder_size
    pubder_size=$(wc -c < "$pubkey_der")
    if [ "$pubder_size" -lt 65 ]; then
        cleanup
        die "Public key DER file too small ($pubder_size bytes)"
    fi

    # Extract raw public key (last 65 bytes)
    tail -c 65 "$pubkey_der" > "$pubkey_bin"

    # Verify we got exactly 65 bytes
    local pubkey_size
    pubkey_size=$(wc -c < "$pubkey_bin")
    if [ "$pubkey_size" -ne 65 ]; then
        cleanup
        die "Expected 65 bytes for uncompressed public key, got $pubkey_size"
    fi

    # Verify first byte is 0x04 (uncompressed marker)
    local first_byte
    first_byte=$(xxd -l 1 -p "$pubkey_bin")
    if [ "$first_byte" != "04" ]; then
        cleanup
        die "Public key should start with 0x04, got 0x$first_byte"
    fi

    # Convert to hex and extract coordinates
    local pubkey_hex x_hex y_hex
    pubkey_hex=$(xxd -p "$pubkey_bin" | tr -d '\n' | tr 'a-f' 'A-F')
    x_hex="${pubkey_hex:2:64}"
    y_hex="${pubkey_hex:66:64}"

    # Validate coordinate lengths
    if [ ${#x_hex} -ne 64 ] || [ ${#y_hex} -ne 64 ]; then
        cleanup
        die "Invalid coordinate lengths (x=${#x_hex}, y=${#y_hex})"
    fi

    info "Calculating compressed public key format"
    # Check Y coordinate parity for compression
    local y_parity prefix
    y_parity=$(echo "ibase=16; $y_hex % 2" | bc)

    if [ "$y_parity" -eq 0 ]; then
        prefix="02"
    else
        prefix="03"
    fi

    local compressed_pubkey="${prefix}${x_hex}"
    local uncompressed_pubkey="04${x_hex}${y_hex}"

    # Final validation - check for point at origin
    local x_zero_check y_zero_check
    x_zero_check=$(echo "$x_hex" | grep -c '^0\+$' || true)
    y_zero_check=$(echo "$y_hex" | grep -c '^0\+$' || true)

    if [ "$x_zero_check" -eq 1 ] && [ "$y_zero_check" -eq 1 ]; then
        warn "Generated point at origin - this may indicate an error"
    fi

    # Output results based on format
    case "$OUTPUT_FORMAT" in
        compressed)
            echo "$compressed_pubkey"
            ;;
        uncompressed)  
            echo "$uncompressed_pubkey"
            ;;
        both)
            echo "$compressed_pubkey"
            echo "$uncompressed_pubkey"
            ;;
    esac
    
    info "Public key generation completed successfully"
    cleanup
}

# Main execution
main() {
    check_dependencies
    
    local priv_hex
    priv_hex=$(read_private_key "$@")
    validate_key_range "$priv_hex"
    generate_public_key "$priv_hex"
}

main "$@"

