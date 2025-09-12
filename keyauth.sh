#!/bin/bash

set -euo pipefail

# Private key authentication command (like sudo for Bitcoin keys)
# Usage: keyauth.sh [command] [args...]

# Parse options  
QUIET=0
VERBOSE=0
LABEL="default"
VALIDATE_ONLY=0
while getopts "qvl:ch" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        l) LABEL="$OPTARG" ;;
        c) VALIDATE_ONLY=1 ;;
        h) 
            cat >&2 << 'EOF'
Usage: keyauth.sh [-q] [-v] [-l label] [-c] [command [args...]]

Authenticate with private key and execute command (like sudo for Bitcoin keys).

Options:
  -q    Quiet mode (suppress informational output)
  -v    Verbose mode (show detailed operations)
  -l    Key label/identifier (default: "default")
  -c    Check/validate authentication only (don't run command)
  -h    Show this help

Examples:
  keyauth.sh                         # Authenticate only
  keyauth.sh send.sh from to 50000   # Authenticate and run send command
  keyauth.sh -c                      # Check if already authenticated
  keyauth.sh -l wallet1 send.sh ...  # Use specific key label

Security Features:
  - Private key never appears in command line
  - Secure prompt with hidden input
  - 60-second timeout with automatic cleanup
  - Memory-only storage (tmpfs when available)
  - Process isolation and secure cleanup

Workflow:
  1. Check if key is already cached (within timeout)
  2. If not, prompt for private key securely
  3. Store key in secure memory with timeout
  4. Execute requested command with key access
  5. Command can retrieve key via keyring.sh -a get

Environment:
  BITCOIN_SESSION_ID                 # Session identifier
  BITCOIN_KEYAUTH_TIMEOUT            # Override default 60s timeout
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

# Check dependencies
check_dependencies() {
    if [[ ! -f "./keyring.sh" ]]; then
        die "keyring.sh not found - required for secure key management"
    fi
}

# Check if private key is already authenticated
is_authenticated() {
    local label="$1"
    
    if ./keyring.sh -q -a status >/dev/null 2>&1; then
        if ./keyring.sh -q -a get -l "$label" >/dev/null 2>&1; then
            info "Private key already authenticated for label: $label"
            return 0
        fi
    fi
    
    return 1
}

# Authenticate private key
authenticate() {
    local label="$1"
    
    info "Authenticating private key for label: $label"
    
    # Check if already authenticated
    if is_authenticated "$label"; then
        return 0
    fi
    
    # Need to authenticate
    if [[ $QUIET -eq 0 ]]; then
        cat >&2 << 'EOF'
🔐 Bitcoin Private Key Authentication Required

This operation requires access to your private key. The key will be:
  ✓ Stored securely in memory only (no disk writes)
  ✓ Protected with 60-second timeout
  ✓ Never exposed in command line history
  ✓ Automatically cleared on timeout/exit

⚠️  SECURITY WARNING: This is educational software only.
    Never use real private keys with significant funds.

EOF
    fi
    
    # Prompt for key using keyring
    if ! ./keyring.sh -q -a auth -l "$label"; then
        die "Authentication failed"
    fi
    
    # Verify authentication worked
    if ! is_authenticated "$label"; then
        die "Authentication verification failed"
    fi
    
    info "Authentication successful - key cached for 60 seconds"
}

# Execute command with authenticated context
execute_with_auth() {
    local label="$1"
    shift
    
    # Set environment for command
    export BITCOIN_KEYRING_LABEL="$label"
    export BITCOIN_KEYRING_ACTIVE="1"
    
    info "Executing command with authenticated context: $*"
    
    # Execute the command
    exec "$@"
}

# Show authentication status
show_auth_status() {
    local label="$1"
    
    local status="unauthenticated"
    local time_remaining=""
    
    if ./keyring.sh -q -a status >/dev/null 2>&1; then
        if ./keyring.sh -q -a get -l "$label" >/dev/null 2>&1; then
            status="authenticated"
            # Get detailed status
            local keyring_status
            keyring_status=$(./keyring.sh -v -a status 2>&1 | grep "Time remaining:" | awk '{print $3}' || echo "unknown")
            time_remaining="($keyring_status remaining)"
        fi
    fi
    
    if [[ $VERBOSE -eq 1 ]]; then
        cat >&2 << EOF
Authentication Status:
  Label: $label
  Status: $status $time_remaining
  Session: ${BITCOIN_SESSION_ID:-$$}
EOF
    else
        echo "$status"
    fi
}

# Main execution
main() {
    check_dependencies
    
    # Handle validation-only mode
    if [[ $VALIDATE_ONLY -eq 1 ]]; then
        show_auth_status "$LABEL"
        if is_authenticated "$LABEL"; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # If no command provided, just authenticate
    if [[ $# -eq 0 ]]; then
        authenticate "$LABEL"
        show_auth_status "$LABEL"
        
        if [[ $QUIET -eq 0 ]]; then
            cat >&2 << 'EOF'

✅ Authentication complete. You can now run commands that require private keys:

Examples:
  send.sh from_address to_address amount    # No private key argument needed
  ./sign.sh transaction_data                # Private key accessed securely
  
The private key will remain cached for 60 seconds.
EOF
        fi
        return 0
    fi
    
    # Authenticate and execute command
    authenticate "$LABEL"
    execute_with_auth "$LABEL" "$@"
}

main "$@"