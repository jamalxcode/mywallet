#!/bin/bash

set -euo pipefail

DEBUG=${DEBUG:-0}

debug() { 
    if [[ $DEBUG -eq 1 ]]; then 
        echo "DEBUG: $*" >&2
    fi
}

usage() {
    cat >&2 << 'EOF'
Usage: echo 'hex_entropy' | ./script.sh
Example: echo 'a1b2c3d4e5f678901234567890123456' | ./script.sh

Input: 32 lowercase hex characters (128 bits, 0-9 a-f)
Output: 12 decimal numbers (0-2047) for BIP39 wordlist indices

Environment: Set DEBUG=1 for verbose output
EOF
    exit 1
}

# Dependency check
for dep in xxd bc; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Error: Required command '$dep' not found in PATH." >&2
        exit 1
    fi
done

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "Error: Required command 'sha256sum' or 'shasum' not found in PATH." >&2
    exit 1
fi

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

# Portable SHA-256 hash - fixed pipeline issue
sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo "Error: No SHA-256 command found (need sha256sum or shasum)" >&2
        exit 1
    fi
}

# Read and validate entropy input
read_entropy() {
    input=$(cat - | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ -z "$input" ]]; then
        echo "Error: No input provided" >&2
        exit 1
    fi
    if ! [[ "$input" =~ ^[0-9a-f]{32}$ ]]; then
        echo "Error: Input must be exactly 32 lowercase hex characters (0-9, a-f)" >&2
        echo "Got: '$input' (${#input} chars)" >&2
        exit 1
    fi
    echo "$input"
}

# Main processing - fixed hash calculation
process_entropy() {
    entropy_hex="$1"
    debug "Processing entropy: $entropy_hex"

    # Calculate SHA-256 hash - fixed to handle binary data properly
    hash_hex=$(echo -n "$entropy_hex" | xxd -r -p | sha256_hex)
    debug "SHA-256 hash: $hash_hex"

    # Convert entropy to binary
    entropy_binary=$(hex_to_binary "$entropy_hex")
    debug "Entropy binary: $entropy_binary (${#entropy_binary} bits)"

    # Convert hash to binary and extract first 4 bits for checksum
    hash_binary=$(hex_to_binary "${hash_hex:0:1}")
    checksum_binary="${hash_binary:0:4}"
    debug "Checksum binary: $checksum_binary"

    # Append checksum to entropy binary (128 + 4 = 132 bits)
    full_binary="${entropy_binary}${checksum_binary}"
    debug "Full binary (entropy + checksum): $full_binary (${#full_binary} bits)"

    # Validate we have exactly 132 bits
    if [ ${#full_binary} -ne 132 ]; then
        echo "Error: Expected 132 bits, got ${#full_binary}" >&2
        exit 1
    fi

    # Split into 12 groups of 11 bits
    for ((i=0; i<12; i++)); do
        start=$((i*11))
        bits="${full_binary:$start:11}"
        if [ ${#bits} -ne 11 ]; then
            echo "Error: Group $i has ${#bits} bits instead of 11" >&2
            exit 1
        fi
        index=$((2#$bits))
        debug "Group $i: $bits -> $index"
        echo "$index"
    done
}

# If no input or help requested, show usage
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

entropy=$(read_entropy)
process_entropy "$entropy"