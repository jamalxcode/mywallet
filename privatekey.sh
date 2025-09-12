#!/bin/bash
set -euo pipefail

# Parse options
QUIET=0
VERBOSE=0
PASSPHRASE=""
while getopts "qvp:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        p) PASSPHRASE="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: privatekey.sh [-q] [-v] [-p passphrase] [mnemonic]
       echo 'word1 word2 ... word12' | privatekey.sh [-q] [-v] [-p passphrase]

Derives BIP32 master private key from BIP39 mnemonic phrase.
Accepts 12/15/18/21/24-word mnemonics.

Options:
  -q    Quiet mode (suppress warnings)
  -v    Verbose mode (show processing steps)  
  -p    Optional BIP39 passphrase
  -h    Show this help

Output format (3 lines):
  <512-bit seed hex>
  <256-bit private key hex>
  <256-bit chain code hex>

Examples:
  echo 'abandon abandon ... abandon about' | privatekey.sh -q
  privatekey.sh -p mypassphrase 'abandon abandon ... abandon about'
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

# Show security warning only if outputting to terminal and not quiet
show_warning() {
    if [[ $QUIET -eq 0 && -t 2 ]]; then
        cat >&2 << 'EOF'
⚠️  WARNING: Never use this script for real funds. For educational/testing only.

EOF
    fi
}

# Find OpenSSL binary
find_openssl() {
    local openssl_paths=("/opt/homebrew/bin/openssl" "/usr/local/bin/openssl" "openssl")
    for path in "${openssl_paths[@]}"; do
        if command -v "$path" >/dev/null 2>&1; then
            local version
            version=$("$path" version 2>/dev/null || echo "unknown")
            if [[ "$version" != *"LibreSSL"* ]]; then
                echo "$path"
                return 0
            fi
        fi
    done
    die "OpenSSL not found. Install with: brew install openssl"
}

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in xxd awk grep; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && die "Missing required commands: ${missing[*]}"
    
    # Check BIP39 wordlist
    local wordlist="./english.txt"
    [[ ! -f "$wordlist" ]] && die "BIP39 wordlist not found at $wordlist"
    echo "$wordlist"
}

# Read and validate mnemonic
read_mnemonic() {
    local mnemonic_raw
    # Try argument first, then stdin
    if [[ $# -gt 0 ]]; then
        mnemonic_raw="$*"
    elif [[ -t 0 ]]; then
        # Interactive mode
        if [[ $QUIET -eq 0 ]]; then
            echo "📥 Enter your 12/15/18/21/24-word mnemonic:" >&2
        fi
        read -r mnemonic_raw
    else
        # Pipeline mode
        read -r mnemonic_raw
    fi
    
    # Normalize mnemonic
    local mnemonic
    mnemonic=$(echo "$mnemonic_raw" | tr '[:upper:]' '[:lower:]' | awk '{$1=$1;print}')
    echo "$mnemonic"
}

# Validate mnemonic
validate_mnemonic() {
    local mnemonic="$1"
    local wordlist="$2"
    
    IFS=' ' read -r -a words <<< "$mnemonic"
    local word_count=${#words[@]}
    local valid_counts=(12 15 18 21 24)
    
    # Check word count
    local valid=0
    for count in "${valid_counts[@]}"; do
        [[ $count -eq $word_count ]] && valid=1 && break
    done
    [[ $valid -eq 0 ]] && die "Invalid number of words: $word_count (expected: 12, 15, 18, 21, or 24)"
    
    # Check each word exists in BIP39 wordlist
    for word in "${words[@]}"; do
        if ! grep -qx "$word" "$wordlist"; then
            die "Invalid BIP39 word: $word"
        fi
    done
    
    info "Mnemonic validation passed ($word_count words)"
}

# Get passphrase
get_passphrase() {
    local passphrase="$1"
    
    # If passphrase not provided via -p flag and interactive mode
    if [[ -z "$passphrase" && -t 0 && $QUIET -eq 0 ]]; then
        echo "🔐 Enter optional passphrase (press Enter to skip):" >&2
        read -rs passphrase
        echo >&2
    fi
    
    echo "$passphrase"
}

# Derive keys from mnemonic
derive_keys() {
    local mnemonic="$1"
    local passphrase="$2"
    local openssl_bin="$3"
    
    local salt="mnemonic$passphrase"
    info "Deriving BIP39 seed with PBKDF2-HMAC-SHA512"
    
    # BIP39 seed derivation (PBKDF2-HMAC-SHA512, 2048 rounds, 64 bytes)
    local seed_hex
    if ! seed_hex=$("$openssl_bin" kdf -keylen 64 -kdfopt digest:SHA512 -kdfopt pass:"$mnemonic" -kdfopt salt:"$salt" -kdfopt iter:2048 PBKDF2 2>/dev/null | xxd -p -c 64); then
        die "Seed derivation failed. Check OpenSSL version and kdf support"
    fi
    
    info "BIP39 seed derived (512 bits)"
    
    # BIP32 master key derivation (HMAC-SHA512, key='Bitcoin seed')
    local seed_bin master_key_hex
    seed_bin=$(echo "$seed_hex" | xxd -r -p)
    master_key_hex=$(echo -n "$seed_bin" | "$openssl_bin" dgst -sha512 -mac HMAC -macopt key:"Bitcoin seed" | awk '{print $2}')
    
    [[ ${#master_key_hex} -ne 128 ]] && die "Unexpected master key length: ${#master_key_hex} hex chars"
    
    local privkey_hex="${master_key_hex:0:64}"
    local chaincode_hex="${master_key_hex:64:64}"
    
    info "BIP32 master private key and chain code derived"
    
    # Output clean data to stdout
    echo "$seed_hex"
    echo "$privkey_hex"  
    echo "$chaincode_hex"
    
    # Summary to stderr if verbose
    if [[ $VERBOSE -eq 1 ]]; then
        cat >&2 << EOF
✅ Derivation complete:
  • BIP39 seed (512 bits): $seed_hex
  • BIP32 private key (256 bits): $privkey_hex
  • BIP32 chain code (256 bits): $chaincode_hex
EOF
    fi
}

# Main execution
main() {
    show_warning
    
    local openssl_bin wordlist mnemonic final_passphrase
    openssl_bin=$(find_openssl)
    wordlist=$(check_dependencies)
    mnemonic=$(read_mnemonic "$@")
    
    validate_mnemonic "$mnemonic" "$wordlist"
    final_passphrase=$(get_passphrase "$PASSPHRASE")
    
    derive_keys "$mnemonic" "$final_passphrase" "$openssl_bin"
}

main "$@"
