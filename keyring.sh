#!/bin/bash

set -euo pipefail

# Secure keyring daemon for Bitcoin toolkit
# Similar to sudo - stores private keys in memory with timeout

# Configuration
KEYRING_DIR="/tmp/.bitcoin-keyring-$$"
KEYRING_SOCKET="$KEYRING_DIR/keyring.sock"
KEYRING_PID_FILE="$KEYRING_DIR/keyring.pid"
KEYRING_TIMEOUT=60  # 1 minute timeout
SESSION_ID="${BITCOIN_SESSION_ID:-$$}"

# Parse options
QUIET=0
VERBOSE=0
ACTION="status"  # status, auth, get, clear, kill
LABEL=""
while getopts "qva:l:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        a) ACTION="$OPTARG" ;;
        l) LABEL="$OPTARG" ;;
        h) 
            cat >&2 << 'EOF'
Usage: keyring.sh [-q] [-v] [-a action] [-l label]

Secure private key management for Bitcoin toolkit (like sudo for keys).

Actions:
  status    Show keyring daemon status (default)
  auth      Authenticate and store private key in memory
  get       Retrieve stored private key (for scripts)
  clear     Clear stored keys and reset timeout
  kill      Stop keyring daemon

Options:
  -q    Quiet mode (suppress informational output)
  -v    Verbose mode (show detailed operations)
  -l    Key label/identifier (default: "default")
  -h    Show this help

Examples:
  keyring.sh -a auth                 # Prompt for private key (1min timeout)
  keyring.sh -a get                  # Get stored key (for scripts)
  keyring.sh -a status               # Check if key is cached
  keyring.sh -a clear                # Clear cached keys
  
Security:
  - Private keys never appear in command line arguments
  - Keys stored in secure memory (ramdisk if available)
  - Automatic timeout after 60 seconds
  - Process isolation and cleanup on exit
  
Environment:
  BITCOIN_SESSION_ID                 # Session identifier
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

# Default label
LABEL="${LABEL:-default}"

# Security checks
check_security() {
    # Check if we're running in a secure environment
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        warn "Running over SSH - private keys may be transmitted over network"
    fi
    
    if [[ "$(umask)" != "077" ]] && [[ "$(umask)" != "0077" ]]; then
        warn "Insecure umask detected - setting to 077"
        umask 077
    fi
    
    info "Security checks completed"
}

# Create secure keyring directory
create_keyring_dir() {
    if [[ ! -d "$KEYRING_DIR" ]]; then
        mkdir -m 700 "$KEYRING_DIR" 2>/dev/null || die "Failed to create secure keyring directory"
        info "Created secure keyring directory: $KEYRING_DIR"
        
        # Try to use tmpfs/ramdisk if available (Linux)
        if command -v mount >/dev/null 2>&1 && [[ -f /proc/mounts ]]; then
            if mount -t tmpfs -o size=1M,mode=700,uid=$(id -u),gid=$(id -g) tmpfs "$KEYRING_DIR" 2>/dev/null; then
                info "Mounted secure tmpfs for keyring"
            fi
        fi
    fi
}

# Cleanup keyring on exit
cleanup_keyring() {
    if [[ -d "$KEYRING_DIR" ]]; then
        # Securely wipe memory files
        if [[ -f "$KEYRING_DIR/keys" ]]; then
            # Overwrite with random data before deletion
            dd if=/dev/urandom of="$KEYRING_DIR/keys" bs=1024 count=1 2>/dev/null || true
            rm -f "$KEYRING_DIR/keys" 2>/dev/null || true
        fi
        
        # Kill daemon if running
        if [[ -f "$KEYRING_PID_FILE" ]]; then
            local daemon_pid
            daemon_pid=$(cat "$KEYRING_PID_FILE" 2>/dev/null || echo "")
            if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
                kill "$daemon_pid" 2>/dev/null || true
            fi
            rm -f "$KEYRING_PID_FILE" 2>/dev/null || true
        fi
        
        # Remove directory
        umount "$KEYRING_DIR" 2>/dev/null || true
        rmdir "$KEYRING_DIR" 2>/dev/null || true
        info "Cleaned up keyring directory"
    fi
}

# Trap cleanup on exit
trap cleanup_keyring EXIT INT TERM

# Check if keyring daemon is running
is_daemon_running() {
    if [[ -f "$KEYRING_PID_FILE" ]]; then
        local daemon_pid
        daemon_pid=$(cat "$KEYRING_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Start keyring daemon
start_daemon() {
    if is_daemon_running; then
        info "Keyring daemon already running"
        return 0
    fi
    
    create_keyring_dir
    
    info "Starting keyring daemon with ${KEYRING_TIMEOUT}s timeout"
    
    # Start daemon in background
    (
        # Daemon process
        exec > /dev/null 2>&1 < /dev/null
        
        local start_time
        start_time=$(date +%s)
        local keys_file="$KEYRING_DIR/keys"
        local timeout_file="$KEYRING_DIR/timeout"
        
        # Store our PID
        echo $$ > "$KEYRING_PID_FILE"
        
        # Main daemon loop
        while true; do
            local current_time
            current_time=$(date +%s)
            
            # Check timeout
            if [[ -f "$timeout_file" ]]; then
                local timeout_at
                timeout_at=$(cat "$timeout_file" 2>/dev/null || echo "0")
                if [[ $current_time -gt $timeout_at ]]; then
                    # Timeout reached - clear keys
                    if [[ -f "$keys_file" ]]; then
                        dd if=/dev/urandom of="$keys_file" bs=1024 count=1 2>/dev/null || true
                        rm -f "$keys_file" 2>/dev/null || true
                    fi
                    rm -f "$timeout_file" 2>/dev/null || true
                fi
            fi
            
            # Check if we should exit (no clients for 5 minutes)
            if [[ $((current_time - start_time)) -gt 300 ]]; then
                break
            fi
            
            sleep 1
        done
        
        # Clean up on daemon exit
        rm -f "$KEYRING_PID_FILE" 2>/dev/null || true
    ) &
    
    # Wait a moment for daemon to start
    sleep 0.1
    
    if is_daemon_running; then
        info "Keyring daemon started successfully"
        return 0
    else
        die "Failed to start keyring daemon"
    fi
}

# Store private key securely
store_key() {
    local key="$1"
    local label="$2"
    
    start_daemon
    
    local keys_file="$KEYRING_DIR/keys"
    local timeout_file="$KEYRING_DIR/timeout"
    
    # Calculate timeout timestamp
    local timeout_at
    timeout_at=$(($(date +%s) + KEYRING_TIMEOUT))
    
    # Store key with label (simple format: label:key)
    {
        # Preserve existing keys for other labels
        if [[ -f "$keys_file" ]]; then
            grep -v "^${label}:" "$keys_file" 2>/dev/null || true
        fi
        # Add new key
        echo "${label}:${key}"
    } > "$keys_file.tmp"
    
    # Atomic move
    mv "$keys_file.tmp" "$keys_file"
    chmod 600 "$keys_file"
    
    # Update timeout
    echo "$timeout_at" > "$timeout_file"
    chmod 600 "$timeout_file"
    
    info "Private key stored securely with ${KEYRING_TIMEOUT}s timeout"
}

# Retrieve private key
get_key() {
    local label="$1"
    
    if ! is_daemon_running; then
        return 1
    fi
    
    local keys_file="$KEYRING_DIR/keys"
    local timeout_file="$KEYRING_DIR/timeout"
    
    # Check timeout
    if [[ -f "$timeout_file" ]]; then
        local timeout_at current_time
        timeout_at=$(cat "$timeout_file" 2>/dev/null || echo "0")
        current_time=$(date +%s)
        if [[ $current_time -gt $timeout_at ]]; then
            info "Key timeout expired"
            return 1
        fi
    fi
    
    # Retrieve key
    if [[ -f "$keys_file" ]]; then
        local key
        key=$(grep "^${label}:" "$keys_file" 2>/dev/null | cut -d: -f2- || echo "")
        if [[ -n "$key" ]]; then
            echo "$key"
            return 0
        fi
    fi
    
    return 1
}

# Prompt for private key securely
prompt_private_key() {
    local label="$1"
    
    echo "🔐 Enter private key for secure storage (${KEYRING_TIMEOUT}s timeout):" >&2
    echo "⚠️  Key will not be echoed or stored in command history" >&2
    echo -n "Private key: " >&2
    
    local key
    # Disable echo and read key
    stty -echo 2>/dev/null || true
    read -r key
    stty echo 2>/dev/null || true
    echo >&2
    
    # Validate key format
    key=$(echo "$key" | tr -d '[:space:]' | tr 'a-f' 'A-F')
    if ! [[ "$key" =~ ^[0-9A-F]{64}$ ]]; then
        die "Invalid private key format (must be 64 hex characters)"
    fi
    
    store_key "$key" "$label"
    echo "✅ Private key authenticated and cached securely" >&2
}

# Show keyring status
show_status() {
    local status="inactive"
    local keys_count=0
    local time_remaining=0
    
    if is_daemon_running; then
        status="active"
        
        local keys_file="$KEYRING_DIR/keys"
        local timeout_file="$KEYRING_DIR/timeout"
        
        if [[ -f "$keys_file" ]]; then
            keys_count=$(wc -l < "$keys_file" 2>/dev/null || echo "0")
        fi
        
        if [[ -f "$timeout_file" ]]; then
            local timeout_at current_time
            timeout_at=$(cat "$timeout_file" 2>/dev/null || echo "0")
            current_time=$(date +%s)
            time_remaining=$((timeout_at - current_time))
            if [[ $time_remaining -lt 0 ]]; then
                time_remaining=0
            fi
        fi
    fi
    
    if [[ $VERBOSE -eq 1 ]]; then
        cat >&2 << EOF
Keyring Status:
  Daemon: $status
  Keys cached: $keys_count
  Time remaining: ${time_remaining}s
  Session: $SESSION_ID
  Directory: $KEYRING_DIR
EOF
    else
        echo "$status"
    fi
}

# Clear cached keys
clear_keys() {
    if is_daemon_running; then
        local keys_file="$KEYRING_DIR/keys"
        local timeout_file="$KEYRING_DIR/timeout"
        
        # Securely wipe keys
        if [[ -f "$keys_file" ]]; then
            dd if=/dev/urandom of="$keys_file" bs=1024 count=1 2>/dev/null || true
            rm -f "$keys_file" 2>/dev/null || true
        fi
        rm -f "$timeout_file" 2>/dev/null || true
        
        info "Cached keys cleared"
    else
        info "No keyring daemon running"
    fi
}

# Kill keyring daemon
kill_daemon() {
    if is_daemon_running; then
        cleanup_keyring
        info "Keyring daemon stopped"
    else
        info "No keyring daemon running"
    fi
}

# Main execution
main() {
    check_security
    
    case "$ACTION" in
        status)
            show_status
            ;;
        auth)
            prompt_private_key "$LABEL"
            ;;
        get)
            if ! get_key "$LABEL"; then
                exit 1
            fi
            ;;
        clear)
            clear_keys
            ;;
        kill)
            kill_daemon
            ;;
        *)
            die "Invalid action: $ACTION (use: status, auth, get, clear, kill)"
            ;;
    esac
}

main "$@"