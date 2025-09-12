#!/bin/bash

set -euo pipefail

# Parse options
QUIET=0
VERBOSE=0
NETWORK="mainnet"
API_PROVIDER="blockstream"  # blockstream, blockcypher, blockchair
UNIT="btc"  # btc, sat
while getopts "qvn:p:u:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        n) NETWORK="$OPTARG" ;;
        p) API_PROVIDER="$OPTARG" ;;
        u) UNIT="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: balance.sh [-q] [-v] [-n network] [-p provider] [-u unit] [address]
       echo 'address' | balance.sh [-q] [-v] [-n network] [-p provider] [-u unit]

Check Bitcoin address balance using public APIs.

Options:
  -q    Quiet mode (suppress warnings)
  -v    Verbose mode (show API requests)
  -n    Network: mainnet, testnet (default: mainnet)
  -p    API provider: blockstream, blockcypher, blockchair (default: blockstream)
  -u    Unit: btc, sat (default: btc)
  -h    Show this help

Output format:
  <balance_value>

Examples:
  balance.sh -n testnet tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh
  echo '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' | balance.sh -u sat
  
Note: Requires internet connection and functioning API endpoints.
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

case "$API_PROVIDER" in
    blockstream|blockcypher|blockchair) ;;
    *) die "Invalid API provider: $API_PROVIDER (use: blockstream, blockcypher, blockchair)" ;;
esac

case "$UNIT" in
    btc|sat) ;;
    *) die "Invalid unit: $UNIT (use: btc, sat)" ;;
esac

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in curl jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ " ${missing[*]} " =~ " jq " ]]; then
            warn "jq not found - will use basic JSON parsing (less reliable)"
        fi
        if [[ " ${missing[*]} " =~ " curl " ]]; then
            die "curl is required for API requests"
        fi
    fi
}

# Basic JSON value extraction (fallback when jq unavailable)
extract_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" | grep -o '[0-9]*$' | head -1
}

# Read and validate address
read_address() {
    local address
    if [[ $# -gt 0 ]]; then
        address="$1"
    else
        read -r address
    fi
    
    address=$(echo "$address" | tr -d '[:space:]')
    [[ -z "$address" ]] && die "No address provided"
    
    # Basic address format validation
    if [[ "$address" =~ ^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$ ]] || \
       [[ "$address" =~ ^3[a-km-zA-HJ-NP-Z1-9]{25,34}$ ]] || \
       [[ "$address" =~ ^bc1[a-z0-9]{39,59}$ ]] || \
       [[ "$address" =~ ^tb1[a-z0-9]{39,59}$ ]]; then
        info "Address format validation passed"
    else
        warn "Address format may be invalid: $address"
    fi
    
    echo "$address"
}

# Convert satoshis to BTC
sat_to_btc() {
    local satoshis="$1"
    echo "scale=8; $satoshis / 100000000" | bc -l 2>/dev/null || echo "0.00000000"
}

# Query balance using Blockstream API
query_blockstream() {
    local address="$1"
    local network="$2"
    
    local base_url
    if [[ "$network" == "testnet" ]]; then
        base_url="https://blockstream.info/testnet/api"
    else
        base_url="https://blockstream.info/api"
    fi
    
    local api_url="${base_url}/address/${address}"
    info "Querying Blockstream API: $api_url"
    
    local response
    if ! response=$(curl -s --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null); then
        die "Failed to connect to Blockstream API"
    fi
    
    if [[ "$response" == *"error"* ]] || [[ "$response" == *"Invalid"* ]]; then
        die "API error: $response"
    fi
    
    # Extract balance (funded_txo_sum - spent_txo_sum)
    local funded spent balance
    if command -v jq >/dev/null 2>&1; then
        funded=$(echo "$response" | jq -r '.chain_stats.funded_txo_sum // 0' 2>/dev/null || echo "0")
        spent=$(echo "$response" | jq -r '.chain_stats.spent_txo_sum // 0' 2>/dev/null || echo "0")
    else
        funded=$(extract_json_value "$response" "funded_txo_sum" || echo "0")
        spent=$(extract_json_value "$response" "spent_txo_sum" || echo "0")
    fi
    
    balance=$((funded - spent))
    info "Funded: $funded sat, Spent: $spent sat, Balance: $balance sat"
    
    echo "$balance"
}

# Query balance using BlockCypher API
query_blockcypher() {
    local address="$1"
    local network="$2"
    
    local network_path
    case "$network" in
        mainnet) network_path="main" ;;
        testnet) network_path="test3" ;;
    esac
    
    local api_url="https://api.blockcypher.com/v1/btc/${network_path}/addrs/${address}/balance"
    info "Querying BlockCypher API: $api_url"
    
    local response
    if ! response=$(curl -s --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null); then
        die "Failed to connect to BlockCypher API"
    fi
    
    if [[ "$response" == *"error"* ]] || [[ "$response" == *"Invalid"* ]]; then
        die "API error: $response"
    fi
    
    # Extract balance
    local balance
    if command -v jq >/dev/null 2>&1; then
        balance=$(echo "$response" | jq -r '.balance // 0' 2>/dev/null || echo "0")
    else
        balance=$(extract_json_value "$response" "balance" || echo "0")
    fi
    
    info "Balance: $balance sat"
    echo "$balance"
}

# Get balance from appropriate API
get_balance() {
    local address="$1"
    local network="$2"
    local provider="$3"
    
    local balance_sat
    case "$provider" in
        blockstream)
            balance_sat=$(query_blockstream "$address" "$network")
            ;;
        blockcypher)
            balance_sat=$(query_blockcypher "$address" "$network")
            ;;
        blockchair)
            warn "Blockchair API not implemented yet, falling back to Blockstream"
            balance_sat=$(query_blockstream "$address" "$network")
            ;;
        *)
            die "Unsupported API provider: $provider"
            ;;
    esac
    
    # Convert to requested unit
    case "$UNIT" in
        sat)
            echo "$balance_sat"
            ;;
        btc)
            sat_to_btc "$balance_sat"
            ;;
    esac
}

# Main execution
main() {
    check_dependencies
    
    local address
    address=$(read_address "$@")
    
    get_balance "$address" "$NETWORK" "$API_PROVIDER"
}

main "$@"