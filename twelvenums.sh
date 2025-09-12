#!/bin/bash

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
Usage: twelvenums.sh [-q] [-v] [hex_entropy]
       echo 'hex_entropy' | twelvenums.sh [-q] [-v]

Input:  32 hex characters (128 bits, 0-9 a-f)
Output: 12 decimal numbers (0-2047) for BIP39 wordlist indices

Options:
  -q    Quiet mode (suppress debug output)
  -v    Verbose mode (show processing steps)
  -h    Show this help

Examples:
  echo 'a1b2c3d4e5f678901234567890123456' | twelvenums.sh
  twelvenums.sh a1b2c3d4e5f678901234567890123456
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
debug() { [[ $VERBOSE -eq 1 ]] && echo "Debug: $*" >&2; }

# Dependency check
check_dependencies() {
    local missing=()
    for dep in xxd bc; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing+=("sha256sum or shasum")
    fi
    [[ ${#missing[@]} -gt 0 ]] && die "Missing required commands: ${missing[*]}"
}

# Fixed hex to binary conversion - bc requires uppercase hex
hex_to_binary() {
    hex="$1"
    binary=""
    i=0
    while [ $i -lt ${#hex} ]; do
        char="${hex:$i:1}"
        # Convert to uppercase for bc
        case "$char" in
            [0-9])
                upper_char="$char"
                ;;
            [a-f])
                case "$char" in
                    a) upper_char="A" ;;
                    b) upper_char="B" ;;
                    c) upper_char="C" ;;
                    d) upper_char="D" ;;
                    e) upper_char="E" ;;
                    f) upper_char="F" ;;
                esac
                ;;
            *)
                echo "Invalid hex character: $char" >&2
                exit 1
                ;;
        esac
        
        bin=$(echo "obase=2; ibase=16; $upper_char" | bc)
        # Pad to 4 bits
        while [ ${#bin} -lt 4 ]; do bin="0$bin"; done
        binary="$binary$bin"
        i=$((i+1))
    done
    echo "$binary"
}

# Portable SHA-256 hash
sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# Read and validate entropy input
read_entropy() {
    local input
    # Try argument first, then stdin
    if [[ $# -gt 0 ]]; then
        input="$1"
    else
        input=$(cat -)
    fi
    
    input=$(echo "$input" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [[ -z "$input" ]] && die "No input provided"
    
    if ! [[ "$input" =~ ^[0-9a-f]{32}$ ]]; then
        die "Input must be exactly 32 hex characters (0-9, a-f). Got: '$input' (${#input} chars)"
    fi
    echo "$input"
}

# Main processing
process_entropy() {
    local entropy_hex="$1"
    debug "Processing entropy: $entropy_hex"

    # Calculate SHA-256 hash
    local hash_hex
    hash_hex=$(echo -n "$entropy_hex" | xxd -r -p | sha256_hex)
    debug "SHA-256 hash: $hash_hex"

    # Convert entropy to binary
    local entropy_binary
    entropy_binary=$(hex_to_binary "$entropy_hex")
    debug "Entropy binary: $entropy_binary (${#entropy_binary} bits)"

    # Convert hash to binary and extract first 4 bits for checksum
    local hash_binary checksum_binary
    hash_binary=$(hex_to_binary "${hash_hex:0:1}")
    checksum_binary="${hash_binary:0:4}"
    debug "Checksum binary: $checksum_binary"

    # Append checksum to entropy binary (128 + 4 = 132 bits)
    local full_binary
    full_binary="${entropy_binary}${checksum_binary}"
    debug "Full binary (entropy + checksum): $full_binary (${#full_binary} bits)"

    # Validate we have exactly 132 bits
    [[ ${#full_binary} -ne 132 ]] && die "Expected 132 bits, got ${#full_binary}"

    # Split into 12 groups of 11 bits and output indices
    for ((i=0; i<12; i++)); do
        local start=$((i*11))
        local bits="${full_binary:$start:11}"
        [[ ${#bits} -ne 11 ]] && die "Group $i has ${#bits} bits instead of 11"
        local index=$((2#$bits))
        debug "Group $i: $bits -> $index"
        echo "$index"
    done
}

# Main execution
main() {
    check_dependencies
    local entropy
    entropy=$(read_entropy "$@")
    process_entropy "$entropy"
}

main "$@"