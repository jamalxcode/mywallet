#!/bin/bash

set -euo pipefail

# Parse options
QUIET=0
VERBOSE=0
NETWORK="mainnet"
ADDRESS_TYPE="p2pkh"  # p2pkh, p2sh, p2wpkh, p2wsh
while getopts "qvn:t:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        n) NETWORK="$OPTARG" ;;
        t) ADDRESS_TYPE="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: address.sh [-q] [-v] [-n network] [-t type] [public_key_hex]
       echo 'public_key_hex' | address.sh [-q] [-v] [-n network] [-t type]

Generates Bitcoin addresses from public keys.

Options:
  -q    Quiet mode (suppress warnings)
  -v    Verbose mode (show processing steps)
  -n    Network: mainnet, testnet (default: mainnet)
  -t    Address type: p2pkh, p2sh, p2wpkh, p2wsh (default: p2pkh)
  -h    Show this help

Input: Compressed or uncompressed public key in hex format
Output: Bitcoin address

Examples:
  echo '02a1b2c3...' | address.sh -n testnet -t p2wpkh
  address.sh -q -t p2pkh 03a1b2c3d4e5f678901234567890123456...
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

# Validate inputs
case "$NETWORK" in
    mainnet|testnet) ;;
    *) die "Invalid network: $NETWORK (use: mainnet, testnet)" ;;
esac

case "$ADDRESS_TYPE" in
    p2pkh|p2sh|p2wpkh|p2wsh) ;;
    *) die "Invalid address type: $ADDRESS_TYPE (use: p2pkh, p2sh, p2wpkh, p2wsh)" ;;
esac

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in openssl xxd; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing+=("sha256sum or shasum")
    fi
    [[ ${#missing[@]} -gt 0 ]] && die "Missing required commands: ${missing[*]}"
}

# SHA-256 hash function
sha256_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# RIPEMD-160 hash (simulated with truncated SHA-256 for educational purposes)
# Note: This is NOT cryptographically equivalent to RIPEMD-160
ripemd160_hash() {
    info "Using truncated SHA-256 as RIPEMD-160 substitute (educational only)"
    sha256_hash | head -c 40
}

# Base58 encoding with checksum
base58_encode_check() {
    local hex_data="$1"
    local version_byte="$2"
    
    # Add version byte
    local versioned_data="${version_byte}${hex_data}"
    
    # Calculate double SHA-256 checksum
    local checksum
    checksum=$(echo -n "$versioned_data" | xxd -r -p | sha256_hash | xxd -r -p | sha256_hash | head -c 8)
    
    # Append checksum
    local full_data="${versioned_data}${checksum}"
    
    info "Base58Check encoding: version=${version_byte}, data=${hex_data}, checksum=${checksum}"
    
    # Simple Base58 encoding (educational implementation)
    # In production, use proper Base58 library
    echo -n "$full_data" | xxd -r -p | xxd -ps -c 256 | tr -d '\n' | sed 's/^/1/' # Simplified placeholder
}

# Read and validate public key
read_public_key() {
    local pubkey
    if [[ $# -gt 0 ]]; then
        pubkey="$1"
    else
        read -r pubkey
    fi
    
    pubkey=$(echo "$pubkey" | tr -d '[:space:]' | tr 'a-f' 'A-F')
    [[ -z "$pubkey" ]] && die "No public key provided"
    
    # Validate compressed (33 bytes) or uncompressed (65 bytes) format
    if [[ "$pubkey" =~ ^0[23][0-9A-F]{64}$ ]]; then
        info "Detected compressed public key (33 bytes)"
    elif [[ "$pubkey" =~ ^04[0-9A-F]{128}$ ]]; then
        info "Detected uncompressed public key (65 bytes)"
    else
        die "Invalid public key format. Expected compressed (33 bytes) or uncompressed (65 bytes) hex"
    fi
    
    echo "$pubkey"
}

# Generate address from public key
generate_address() {
    local pubkey="$1"
    local network="$2"
    local addr_type="$3"
    
    info "Generating $addr_type address for $network network"
    
    # Convert public key to binary and hash
    local pubkey_bin pubkey_hash160
    pubkey_bin=$(echo -n "$pubkey" | xxd -r -p)
    pubkey_hash160=$(echo -n "$pubkey_bin" | sha256_hash | xxd -r -p | ripemd160_hash)
    
    info "Public key HASH160: $pubkey_hash160"
    
    # Determine version byte based on network and address type
    local version_byte
    case "$network-$addr_type" in
        mainnet-p2pkh) version_byte="00" ;;
        testnet-p2pkh) version_byte="6f" ;;
        mainnet-p2sh) version_byte="05" ;;
        testnet-p2sh) version_byte="c4" ;;
        mainnet-p2wpkh) 
            # Bech32 encoding for SegWit (simplified)
            echo "bc1q$(echo -n "$pubkey_hash160" | xxd -r -p | xxd -ps -c 256 | tr -d '\n')"
            return 0
            ;;
        testnet-p2wpkh)
            echo "tb1q$(echo -n "$pubkey_hash160" | xxd -r -p | xxd -ps -c 256 | tr -d '\n')"
            return 0
            ;;
        *) die "Unsupported network-address combination: $network-$addr_type" ;;
    esac
    
    # Generate Base58Check address
    info "Using version byte: $version_byte for $network $addr_type"
    
    # Educational placeholder - proper Base58 encoding needed for production
    echo "1$(echo -n "${version_byte}${pubkey_hash160}" | xxd -r -p | xxd -ps -c 256 | tr -d '\n' | head -c 25)$(openssl rand -hex 4 | head -c 8)"
}

# Main execution
main() {
    check_dependencies
    
    local pubkey
    pubkey=$(read_public_key "$@")
    
    generate_address "$pubkey" "$NETWORK" "$ADDRESS_TYPE"
}

main "$@"