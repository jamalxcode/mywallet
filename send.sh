#!/bin/bash

set -euo pipefail

# Secure Bitcoin transaction sender using keyring authentication
# Usage: keyauth.sh send-secure.sh from_address to_address amount_sat

# Parse options
QUIET=0
VERBOSE=0
NETWORK=""  # Will auto-detect from network.sh if not specified
FEE_RATE="10"  # satoshis per byte
DRY_RUN=0
BROADCAST=1
KEY_LABEL="default"
while getopts "qvn:f:db:l:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        n) NETWORK="$OPTARG" ;;
        f) FEE_RATE="$OPTARG" ;;
        d) DRY_RUN=1 ;;
        b) BROADCAST="$OPTARG" ;;
        l) KEY_LABEL="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: send-secure.sh [-q] [-v] [-n network] [-f fee_rate] [-d] [-b 0|1] [-l label] from_address to_address amount_sat

🔐 SECURE Bitcoin transaction sender - requires keyauth.sh authentication.

Options:
  -q    Quiet mode (suppress warnings and progress)
  -v    Verbose mode (show transaction details)
  -n    Network: mainnet, testnet (auto-detected if not specified)
  -f    Fee rate in sat/byte (default: 10)
  -d    Dry run mode (create transaction but don't broadcast)
  -b    Broadcast transaction: 1=yes, 0=no (default: 1, disabled in dry-run)
  -l    Key label for keyring (default: "default")
  -h    Show this help

Arguments:
  from_address    Source Bitcoin address (must match authenticated private key)
  to_address      Destination Bitcoin address  
  amount_sat      Amount to send in satoshis

🔐 SECURE AUTHENTICATION REQUIRED:
  This command requires prior authentication with keyauth.sh:
  
  Method 1 (Recommended):
    keyauth.sh send-secure.sh from_addr to_addr amount
    
  Method 2:
    keyauth.sh                          # Authenticate first
    send-secure.sh from_addr to_addr amount     # Then send

Output:
  <transaction_id>    (if broadcast successful)
  <raw_transaction>   (if dry-run or broadcast disabled)

Examples:
  # Authenticate and send in one command (recommended)
  keyauth.sh send-secure.sh -n testnet -d tb1qfrom... tb1qto... 50000

  # Two-step process
  keyauth.sh                    # Prompts for private key (60s timeout)
  send-secure.sh -f 5 from... to... 100000    # Uses cached key

  # With specific key label  
  keyauth.sh -l wallet1 send-secure.sh from... to... 25000

SECURITY FEATURES:
  ✓ Private key never appears in command line
  ✓ No exposure in shell history
  ✓ Secure memory-only storage
  ✓ Automatic 60-second timeout
  ✓ Process isolation and cleanup

⚠️  Educational software only - never use with real funds.
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

# Check required arguments
if [[ $# -lt 3 ]]; then
    cat >&2 << 'EOF'
❌ Error: Insufficient arguments

Usage: send-secure.sh from_address to_address amount_sat

🔐 AUTHENTICATION REQUIRED:
  This command requires secure authentication:
  
  keyauth.sh send-secure.sh from_address to_address amount_sat

Examples:
  keyauth.sh send-secure.sh tb1qfrom... tb1qto... 50000
  keyauth.sh send-secure.sh -d -n testnet from... to... 25000
EOF
    exit 1
fi

FROM_ADDRESS="$1"
TO_ADDRESS="$2"
AMOUNT_SAT="$3"

# Check for keyring authentication
check_keyring_auth() {
    if [[ -z "${BITCOIN_KEYRING_ACTIVE:-}" ]]; then
        cat >&2 << 'EOF'
❌ Error: Private key authentication required

This command must be run through keyauth.sh for secure key access.

🔐 SECURE USAGE:
  keyauth.sh send-secure.sh from_address to_address amount_sat

OR authenticate separately:
  keyauth.sh                    # Authenticate (60s timeout)
  send-secure.sh from to amount        # Use cached key

This prevents private keys from appearing in:
  ✗ Command line arguments  
  ✗ Shell history
  ✗ Process lists
  ✗ Log files
EOF
        exit 1
    fi
    
    info "Keyring authentication detected - proceeding securely"
}

# Get private key from secure keyring
get_private_key() {
    local label="${BITCOIN_KEYRING_LABEL:-$KEY_LABEL}"
    
    if [[ ! -f "./keyring.sh" ]]; then
        die "keyring.sh not found - cannot access secure private key storage"
    fi
    
    local private_key
    if ! private_key=$(./keyring.sh -q -a get -l "$label" 2>/dev/null); then
        die "Failed to retrieve private key from keyring - authentication may have expired"
    fi
    
    if [[ -z "$private_key" ]]; then
        die "Empty private key retrieved from keyring"
    fi
    
    info "Private key retrieved securely from keyring"
    echo "$private_key"
}

# Auto-detect network if not specified
if [[ -z "$NETWORK" ]]; then
    if [[ -f "./network.sh" ]]; then
        NETWORK=$(./network.sh 2>/dev/null || echo "mainnet")
        info "Auto-detected network: $NETWORK"
    else
        NETWORK="mainnet"
        warn "Could not auto-detect network, using mainnet"
    fi
fi

# In dry-run mode, disable broadcasting
if [[ $DRY_RUN -eq 1 ]]; then
    BROADCAST=0
    info "Dry-run mode enabled - transaction will not be broadcast"
fi

# Validate inputs
case "$NETWORK" in
    mainnet|testnet) ;;
    *) die "Invalid network: $NETWORK (use: mainnet, testnet)" ;;
esac

# Validate amount
if ! [[ "$AMOUNT_SAT" =~ ^[0-9]+$ ]] || [[ $AMOUNT_SAT -lt 546 ]]; then
    die "Invalid amount: $AMOUNT_SAT (must be integer >= 546 satoshis)"
fi

# Validate fee rate
if ! [[ "$FEE_RATE" =~ ^[0-9]+$ ]] || [[ $FEE_RATE -lt 1 ]]; then
    die "Invalid fee rate: $FEE_RATE (must be integer >= 1 sat/byte)"
fi

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in curl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    
    # Check for local scripts
    local scripts=("./balance.sh" "./public_key.sh" "./address.sh")
    for script in "${scripts[@]}"; do
        [[ ! -f "$script" ]] && missing+=("$script")
    done
    
    [[ ${#missing[@]} -gt 0 ]] && die "Missing dependencies: ${missing[*]}"
}

# Get UTXOs for address
get_utxos() {
    local address="$1"
    local network="$2"
    
    local base_url
    if [[ "$network" == "testnet" ]]; then
        base_url="https://blockstream.info/testnet/api"
    else
        base_url="https://blockstream.info/api"
    fi
    
    local api_url="${base_url}/address/${address}/utxo"
    info "Fetching UTXOs from: $api_url"
    
    local response
    if ! response=$(curl -s --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null); then
        die "Failed to fetch UTXOs from API"
    fi
    
    if [[ "$response" == "[]" ]]; then
        die "No UTXOs found for address: $address"
    fi
    
    echo "$response"
}

# Select UTXOs for spending
select_utxos() {
    local utxos="$1"
    local target_amount="$2"
    local estimated_fee="$3"
    
    local total_needed=$((target_amount + estimated_fee))
    info "Target amount: $target_amount sat, Estimated fee: $estimated_fee sat, Total needed: $total_needed sat"
    
    # Simple UTXO selection - use largest UTXO first (educational implementation)
    # Production should implement proper coin selection algorithms
    
    echo "$utxos" | grep -o '"value":[0-9]*' | grep -o '[0-9]*' | head -1
}

# Estimate transaction fee
estimate_fee() {
    local num_inputs="$1"
    local num_outputs="$2"
    local fee_rate="$3"
    
    # Rough estimation: 180 bytes per input + 34 bytes per output + 10 bytes overhead
    local tx_size=$((num_inputs * 180 + num_outputs * 34 + 10))
    local fee=$((tx_size * fee_rate))
    
    info "Estimated transaction size: $tx_size bytes, Fee: $fee sat ($fee_rate sat/byte)"
    echo "$fee"
}

# Create raw transaction (educational placeholder)
create_raw_transaction() {
    local from_addr="$1"
    local to_addr="$2" 
    local amount="$3"
    local private_key="$4"
    local utxos="$5"
    
    info "Creating raw transaction..."
    info "From: $from_addr"
    info "To: $to_addr"
    info "Amount: $amount sat"
    info "Private key: [SECURE - not logged]"
    
    # This is a educational placeholder for transaction creation
    # Real implementation would require:
    # 1. Parse UTXO data and select appropriate inputs
    # 2. Create proper transaction structure with inputs/outputs
    # 3. Generate scriptSig for each input
    # 4. Sign transaction with private key using secp256k1
    # 5. Serialize transaction to hex format
    
    warn "Transaction creation is educational placeholder only"
    
    # Generate a fake transaction hash for demonstration
    local fake_txid
    fake_txid=$(echo -n "${from_addr}${to_addr}${amount}$(date +%s)" | shasum -a 256 | cut -d' ' -f1)
    
    info "Generated transaction ID: $fake_txid"
    echo "$fake_txid"
}

# Broadcast transaction
broadcast_transaction() {
    local raw_tx="$1"
    local network="$2"
    
    if [[ $BROADCAST -eq 0 ]]; then
        info "Broadcasting disabled - raw transaction: $raw_tx"
        echo "$raw_tx"
        return 0
    fi
    
    warn "Transaction broadcasting not implemented - this is educational software only"
    info "Raw transaction would be broadcast: $raw_tx"
    
    # In a real implementation, this would POST the raw transaction to a node
    echo "$raw_tx"
}

# Verify address ownership
verify_address_ownership() {
    local address="$1"
    local private_key="$2"
    local network="$3"
    
    info "Verifying address ownership..."
    
    # Generate public key from private key
    local public_key
    if ! public_key=$(echo "$private_key" | ./public_key.sh -q -f compressed 2>/dev/null); then
        die "Failed to generate public key from private key"
    fi
    
    # Generate address from public key
    local derived_address
    if [[ -f "./address.sh" ]]; then
        if ! derived_address=$(echo "$public_key" | ./address.sh -q -n "$network" 2>/dev/null); then
            warn "Could not verify address ownership (address.sh failed)"
            return 0
        fi
        
        if [[ "$address" != "$derived_address" ]]; then
            die "Address ownership verification failed: $address != $derived_address"
        fi
        
        info "Address ownership verified"
    else
        warn "Cannot verify address ownership - address.sh not found"
    fi
}

# Main execution
main() {
    # Security checks first
    check_keyring_auth
    check_dependencies
    
    warn "⚠️  EDUCATIONAL SOFTWARE ONLY - DO NOT USE WITH REAL FUNDS"
    
    # Get private key from secure keyring
    local private_key
    private_key=$(get_private_key)
    
    # Verify address ownership
    verify_address_ownership "$FROM_ADDRESS" "$private_key" "$NETWORK"
    
    # Check current balance
    local current_balance
    if current_balance=$(./balance.sh -q -n "$NETWORK" -u sat "$FROM_ADDRESS" 2>/dev/null); then
        info "Current balance: $current_balance sat"
        
        if [[ $current_balance -lt $AMOUNT_SAT ]]; then
            die "Insufficient balance: $current_balance sat < $AMOUNT_SAT sat"
        fi
    else
        warn "Could not check current balance - proceeding anyway"
    fi
    
    # Get UTXOs
    local utxos
    utxos=$(get_utxos "$FROM_ADDRESS" "$NETWORK")
    
    # Estimate fee
    local estimated_fee
    estimated_fee=$(estimate_fee 1 2 "$FEE_RATE")  # Assume 1 input, 2 outputs (recipient + change)
    
    # Check total amount including fee
    local total_needed=$((AMOUNT_SAT + estimated_fee))
    if [[ -n "${current_balance:-}" ]] && [[ $current_balance -lt $total_needed ]]; then
        die "Insufficient balance for amount + fee: $current_balance sat < $total_needed sat"
    fi
    
    # Create and broadcast transaction
    local raw_tx
    raw_tx=$(create_raw_transaction "$FROM_ADDRESS" "$TO_ADDRESS" "$AMOUNT_SAT" "$private_key" "$utxos")
    
    broadcast_transaction "$raw_tx" "$NETWORK"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        info "Dry-run completed successfully - no funds were moved"
        echo "✅ Transaction created successfully (dry-run mode)" >&2
    else
        echo "⚠️  Transaction created but not broadcast (educational mode)" >&2
    fi
}

main "$@"