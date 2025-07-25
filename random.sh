#!/usr/bin/env bash

# Bitcoin Mnemonic Entropy Generator
# Usage: ./gen_entropy.sh [hex|binary|checksum] [hex_value]
# Generates 128-bit entropy for BIP39 mnemonics and calculates checksum bits.
# For educational use only. Do NOT use for production wallets.

set -euo pipefail  # Strict error handling

FORMAT="${1:-hex}"
ENTROPY_VALUE="${2:-}"

# Security warning
show_warning() {
    cat << 'EOF'
⚠️  SECURITY WARNING:
This tool generates cryptographic entropy for educational purposes.
For actual Bitcoin storage, use hardware wallets or certified software.
Never run this on internet-connected machines for production keys.
EOF
}

# Check dependencies (cross-platform)
check_dependencies() {
    local missing=()
    command -v openssl >/dev/null 2>&1 || missing+=("openssl")
    command -v xxd >/dev/null 2>&1 || missing+=("xxd")
    # Check for sha256sum or fallback to openssl
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing+=("sha256sum or shasum")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

# Calculate SHA-256 hash (cross-platform)
sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# Generate entropy and/or checksum
generate_entropy() {
    local format="$1"
    case "$format" in
        hex)
            echo "128-bit entropy (16 bytes) for 12-word mnemonic:"
            openssl rand -hex 16
            ;;
        binary)
            echo "128-bit entropy in binary format:"
            openssl rand 16 | xxd -b -c 16 | awk '{for(i=2;i<=17;i++) printf "%s", $i}' | head -c 128; echo
            ;;
        checksum)
            if [[ -z "$ENTROPY_VALUE" ]]; then
                echo "Usage: $0 checksum <hex_entropy>" >&2
                exit 1
            fi
            if [[ ! "$ENTROPY_VALUE" =~ ^[0-9a-fA-F]{32}$ ]]; then
                echo "Error: Entropy must be 32 hex characters (128 bits)" >&2
                exit 1
            fi
            echo "Calculating checksum for: $ENTROPY_VALUE"
            # Get SHA-256 hash, extract first byte, convert to binary, take first 4 bits (BIP39)
            first_byte_bin=$(echo -n "$ENTROPY_VALUE" | xxd -r -p | openssl dgst -sha256 -binary | head -c1 | xxd -b | awk '{print $2}')
            checksum_bits="${first_byte_bin:0:4}"
            echo "Checksum (first 4 bits): $checksum_bits"
            ;;
        *)
            echo "Usage: $0 [hex|binary|checksum] [hex_value]" >&2
            echo "  hex      - Generate 128-bit entropy in hexadecimal"
            echo "  binary   - Generate 128-bit entropy in binary"
            echo "  checksum - Calculate checksum for given 128-bit hex entropy"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    show_warning
    echo
    check_dependencies
    generate_entropy "$FORMAT"
}

main "$@"
