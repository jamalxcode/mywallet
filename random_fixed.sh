#!/usr/bin/env bash

# Bitcoin Mnemonic Entropy Generator - Fixed Version
# Usage: ./random_fixed.sh [-q] [-v] [hex|binary|checksum] [hex_value]
# Generates 128-bit entropy for BIP39 mnemonics and calculates checksum bits.

set -euo pipefail

# Parse options
QUIET=0
VERBOSE=0
while getopts "qvh" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        h) 
            cat >&2 << 'EOF'
Usage: random_fixed.sh [-q] [-v] [hex|binary|checksum] [hex_value]
  -q         Quiet mode (suppress warnings and info)
  -v         Verbose mode (show progress)
  -h         Show this help
  
  hex        Generate 128-bit entropy in hexadecimal (default)
  binary     Generate 128-bit entropy in binary
  checksum   Calculate checksum for given 128-bit hex entropy
EOF
            exit 0
            ;;
        *) exit 1 ;;
    esac
done
shift $((OPTIND-1))

FORMAT="${1:-hex}"
ENTROPY_VALUE="${2:-}"

# Logging functions
warn() { [[ $QUIET -eq 0 ]] && echo "Warning: $*" >&2; }
info() { [[ $VERBOSE -eq 1 ]] && echo "Info: $*" >&2; }
die() { echo "Error: $*" >&2; exit 1; }

# Show security warning only if outputting to terminal and not quiet
show_warning() {
    if [[ $QUIET -eq 0 && -t 2 ]]; then
        cat >&2 << 'EOF'
⚠️  SECURITY WARNING:
This tool generates cryptographic entropy for educational purposes.
For actual Bitcoin storage, use hardware wallets or certified software.
Never run this on internet-connected machines for production keys.

EOF
    fi
}

# Check dependencies (cross-platform)
check_dependencies() {
    local missing=()
    command -v openssl >/dev/null 2>&1 || missing+=("openssl")
    command -v xxd >/dev/null 2>&1 || missing+=("xxd")
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing+=("sha256sum or shasum")
    fi
    [[ ${#missing[@]} -gt 0 ]] && die "Missing required commands: ${missing[*]}"
    info "Dependencies check passed"
}

# Calculate SHA-256 hash (cross-platform)
sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# Generate entropy
generate_entropy() {
    local format="$1"
    case "$format" in
        hex)
            info "Generating 128-bit entropy in hexadecimal"
            openssl rand -hex 16 || die "Failed to generate entropy"
            ;;
        binary)
            info "Generating 128-bit entropy in binary"
            local hex_entropy
            hex_entropy=$(openssl rand -hex 16) || die "Failed to generate entropy"
            echo -n "$hex_entropy" | xxd -r -p | xxd -b -c 16 | awk '{for(i=2;i<=17;i++) printf "%s", $i}' | head -c 128
            echo
            ;;
        checksum)
            [[ -z "$ENTROPY_VALUE" ]] && die "checksum mode requires hex entropy as argument"
            [[ ! "$ENTROPY_VALUE" =~ ^[0-9a-fA-F]{32}$ ]] && die "Entropy must be 32 hex characters (128 bits)"
            info "Calculating checksum for: $ENTROPY_VALUE"
            local first_byte_bin
            first_byte_bin=$(echo -n "$ENTROPY_VALUE" | xxd -r -p | sha256_hex | head -c2 | xxd -r -p | xxd -b | awk '{print $2}')
            local checksum_bits="${first_byte_bin:0:4}"
            echo "$checksum_bits"
            ;;
        *)
            die "Invalid format: $format. Use hex, binary, or checksum"
            ;;
    esac
}

# Main execution
main() {
    show_warning
    check_dependencies
    generate_entropy "$FORMAT"
}

main "$@"