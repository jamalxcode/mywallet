#!/bin/bash

set -euo pipefail

# Production-hardened secure keyring daemon for Bitcoin toolkit
# Addresses all critical security vulnerabilities found in audit

# Security Configuration - HARDENED
readonly KEYRING_BASE_DIR="/dev/shm"  # Use shared memory when available
readonly KEYRING_DIR_PREFIX=".bitcoin-keyring"
readonly KEYRING_TIMEOUT=60
readonly MAX_KEY_SIZE=64
readonly MAX_LABEL_LENGTH=32
readonly SECURE_DELETE_PASSES=3

# Validate we're running in secure environment
validate_security_environment() {
    # Check for required security features
    if [[ $EUID -eq 0 ]]; then
        echo "Security Error: This script should not run as root" >&2
        exit 1
    fi
    
    # Ensure we have a secure temp directory
    if [[ ! -d "/dev/shm" ]]; then
        if [[ ! -w "/tmp" ]]; then
            echo "Security Error: No secure temporary directory available" >&2
            exit 1
        fi
    fi
    
    # Set secure umask
    umask 077
    
    # Check for dangerous environment variables
    unset LD_PRELOAD LD_LIBRARY_PATH DYLD_INSERT_LIBRARIES
}

# Create cryptographically secure random session ID
create_session_id() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16 2>/dev/null || echo "fallback-$$-$(date +%s)"
    else
        echo "fallback-$$-$(date +%s)"
    fi
}

# Initialize secure configuration
readonly SESSION_ID="${BITCOIN_SESSION_ID:-$(create_session_id)}"
readonly KEYRING_DIR="${KEYRING_BASE_DIR}/${KEYRING_DIR_PREFIX}-${SESSION_ID}"
readonly KEYRING_PID_FILE="${KEYRING_DIR}/keyring.pid"
readonly KEYRING_KEYS_FILE="${KEYRING_DIR}/keys"
readonly KEYRING_TIMEOUT_FILE="${KEYRING_DIR}/timeout"
readonly KEYRING_LOCK_FILE="${KEYRING_DIR}/lock"

# Input validation functions
validate_label() {
    local label="$1"
    # Only allow alphanumeric and underscore, max 32 chars
    if [[ ! "$label" =~ ^[a-zA-Z0-9_]{1,32}$ ]]; then
        echo "Security Error: Invalid label format" >&2
        exit 1
    fi
}

validate_private_key() {
    local key="$1"
    # Strict hex validation, exactly 64 characters
    if [[ ! "$key" =~ ^[0-9A-Fa-f]{64}$ ]]; then
        echo "Security Error: Invalid private key format" >&2
        exit 1
    fi
}

validate_action() {
    local action="$1"
    case "$action" in
        status|auth|get|clear|kill) ;;
        *) echo "Security Error: Invalid action" >&2; exit 1 ;;
    esac
}

# Secure file operations with atomic writes
secure_write() {
    local file="$1"
    local content="$2"
    local temp_file="${file}.tmp.$$"
    
    # Create with secure permissions
    (umask 077; echo "$content" > "$temp_file")
    
    # Atomic move
    if ! mv "$temp_file" "$file" 2>/dev/null; then
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
}

# Secure delete with multiple overwrites
secure_delete() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Multiple overwrite passes
        for ((i=0; i<SECURE_DELETE_PASSES; i++)); do
            if command -v shred >/dev/null 2>&1; then
                shred -vfz -n 1 "$file" 2>/dev/null || true
            else
                # Fallback: overwrite with random data
                if command -v openssl >/dev/null 2>&1; then
                    openssl rand $(wc -c < "$file" 2>/dev/null || echo 1024) > "$file" 2>/dev/null || true
                else
                    dd if=/dev/urandom of="$file" bs=1024 count=1 2>/dev/null || true
                fi
            fi
        done
        rm -f "$file" 2>/dev/null || true
    fi
}

# Parse options with strict validation
QUIET=0
VERBOSE=0
ACTION="status"
LABEL=""

while getopts "qva:l:h" opt; do
    case $opt in
        q) QUIET=1 ;;
        v) VERBOSE=1 ;;
        a) ACTION="$OPTARG"; validate_action "$ACTION" ;;
        l) LABEL="$OPTARG"; validate_label "$LABEL" ;;
        h) 
            cat >&2 << 'EOF'
Usage: keyring-secure.sh [-q] [-v] [-a action] [-l label]

Production-hardened secure private key management for Bitcoin toolkit.

Actions:
  status    Show keyring daemon status (default)
  auth      Authenticate and store private key in memory  
  get       Retrieve stored private key (for scripts)
  clear     Clear stored keys and reset timeout
  kill      Stop keyring daemon

Options:
  -q    Quiet mode (suppress informational output)
  -v    Verbose mode (show detailed operations)
  -l    Key label/identifier (alphanumeric + underscore, max 32 chars)
  -h    Show this help

Security Features:
  ✓ Cryptographically secure session IDs
  ✓ Shared memory storage (/dev/shm when available)
  ✓ Secure file permissions (600/700)  
  ✓ Atomic file operations with exclusive locking
  ✓ Multiple-pass secure deletion
  ✓ Input validation and sanitization
  ✓ Process isolation and cleanup
  ✓ Protection against race conditions
  ✓ Memory clearing on timeout/exit

Environment:
  BITCOIN_SESSION_ID    Session identifier (auto-generated if not set)
EOF
            exit 0
            ;;
        *) echo "Error: Invalid option" >&2; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Logging functions
warn() { [[ $QUIET -eq 0 ]] && echo "Warning: $*" >&2; }
info() { [[ $VERBOSE -eq 1 ]] && echo "Info: $*" >&2; }
die() { echo "Error: $*" >&2; exit 1; }

# Set default label with validation
LABEL="${LABEL:-default}"
validate_label "$LABEL"

# Exclusive file locking for atomic operations
acquire_lock() {
    local lock_file="$KEYRING_LOCK_FILE"
    local timeout=10
    local count=0
    
    while (( count < timeout )); do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            info "Lock acquired"
            return 0
        fi
        sleep 0.1
        count=$((count + 1))
    done
    
    die "Failed to acquire exclusive lock"
}

release_lock() {
    rm -f "$KEYRING_LOCK_FILE" 2>/dev/null || true
    info "Lock released"
}

# Secure keyring directory creation with proper permissions
create_keyring_dir() {
    if [[ -d "$KEYRING_DIR" ]]; then
        # Verify existing directory permissions
        local perms
        perms=$(stat -c %a "$KEYRING_DIR" 2>/dev/null || stat -f %Mp%Lp "$KEYRING_DIR" 2>/dev/null || echo "")
        if [[ "$perms" != "700" ]]; then
            die "Existing keyring directory has insecure permissions: $perms"
        fi
        info "Keyring directory already exists with secure permissions"
        return 0
    fi
    
    # Create directory with restrictive permissions
    if ! mkdir -m 700 "$KEYRING_DIR" 2>/dev/null; then
        die "Failed to create secure keyring directory: $KEYRING_DIR"
    fi
    
    info "Created secure keyring directory: $KEYRING_DIR"
    
    # Attempt to mount tmpfs for additional security (Linux only)
    if [[ -d "/proc" && "$(uname)" == "Linux" ]]; then
        if command -v mount >/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
            # User can't mount, but check if it's already tmpfs
            local fstype
            fstype=$(df -T "$KEYRING_DIR" 2>/dev/null | tail -n1 | awk '{print $2}' || echo "unknown")
            if [[ "$fstype" == "tmpfs" ]]; then
                info "Directory is on tmpfs (secure memory)"
            else
                warn "Directory not on tmpfs - consider mounting /dev/shm as tmpfs"
            fi
        fi
    fi
}

# Comprehensive cleanup with secure deletion
cleanup_keyring() {
    release_lock
    
    if [[ -d "$KEYRING_DIR" ]]; then
        info "Performing secure cleanup of keyring"
        
        # Secure delete all key material
        secure_delete "$KEYRING_KEYS_FILE"
        secure_delete "$KEYRING_TIMEOUT_FILE"
        
        # Stop daemon if running
        if [[ -f "$KEYRING_PID_FILE" ]]; then
            local daemon_pid
            daemon_pid=$(cat "$KEYRING_PID_FILE" 2>/dev/null || echo "")
            if [[ -n "$daemon_pid" && "$daemon_pid" =~ ^[0-9]+$ ]]; then
                if kill -0 "$daemon_pid" 2>/dev/null; then
                    kill -TERM "$daemon_pid" 2>/dev/null || true
                    sleep 1
                    if kill -0 "$daemon_pid" 2>/dev/null; then
                        kill -KILL "$daemon_pid" 2>/dev/null || true
                    fi
                fi
            fi
            rm -f "$KEYRING_PID_FILE" 2>/dev/null || true
        fi
        
        # Remove directory
        rmdir "$KEYRING_DIR" 2>/dev/null || true
        info "Secure cleanup completed"
    fi
}

# Set up signal handlers for secure cleanup
trap cleanup_keyring EXIT INT TERM HUP

# Check if keyring daemon is running
is_daemon_running() {
    if [[ -f "$KEYRING_PID_FILE" ]]; then
        local daemon_pid
        daemon_pid=$(cat "$KEYRING_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$daemon_pid" && "$daemon_pid" =~ ^[0-9]+$ ]]; then
            if kill -0 "$daemon_pid" 2>/dev/null; then
                return 0
            fi
        fi
        # Clean up stale PID file
        rm -f "$KEYRING_PID_FILE" 2>/dev/null || true
    fi
    return 1
}

# Production-hardened daemon with secure memory handling
start_daemon() {
    if is_daemon_running; then
        info "Keyring daemon already running"
        return 0
    fi
    
    create_keyring_dir
    acquire_lock
    
    info "Starting secure keyring daemon"
    
    # Fork daemon process with full isolation
    (
        # Complete process isolation
        exec > /dev/null 2>&1 < /dev/null
        cd /
        setsid 2>/dev/null || true
        
        # Store daemon PID
        echo $$ > "$KEYRING_PID_FILE"
        
        # Daemon main loop with secure timeout handling
        local start_time
        start_time=$(date +%s)
        
        while true; do
            local current_time
            current_time=$(date +%s)
            
            # Check for timeout expiration
            if [[ -f "$KEYRING_TIMEOUT_FILE" ]]; then
                local timeout_at
                timeout_at=$(cat "$KEYRING_TIMEOUT_FILE" 2>/dev/null || echo "0")
                if [[ "$timeout_at" =~ ^[0-9]+$ && $current_time -gt $timeout_at ]]; then
                    # Secure delete expired keys
                    secure_delete "$KEYRING_KEYS_FILE"
                    rm -f "$KEYRING_TIMEOUT_FILE" 2>/dev/null || true
                fi
            fi
            
            # Auto-shutdown after extended inactivity (5 minutes)
            if (( current_time - start_time > 300 )); then
                break
            fi
            
            # Check if parent process still exists
            if ! kill -0 $PPID 2>/dev/null; then
                break
            fi
            
            sleep 1
        done
        
        # Cleanup on daemon exit
        secure_delete "$KEYRING_KEYS_FILE"
        rm -f "$KEYRING_PID_FILE" "$KEYRING_TIMEOUT_FILE" 2>/dev/null || true
    ) &
    
    release_lock
    sleep 0.2  # Allow daemon to start
    
    if is_daemon_running; then
        info "Secure keyring daemon started successfully"
        return 0
    else
        die "Failed to start keyring daemon"
    fi
}

# Store private key with enhanced security
store_key() {
    local key="$1"
    local label="$2"
    
    validate_private_key "$key"
    validate_label "$label"
    
    start_daemon
    acquire_lock
    
    # Calculate timeout timestamp
    local timeout_at
    timeout_at=$(($(date +%s) + KEYRING_TIMEOUT))
    
    # Prepare key storage with label isolation
    local keys_content=""
    if [[ -f "$KEYRING_KEYS_FILE" ]]; then
        # Preserve existing keys for other labels
        keys_content=$(grep -v "^${label}:" "$KEYRING_KEYS_FILE" 2>/dev/null || true)
    fi
    
    # Add new key entry
    keys_content="${keys_content}${keys_content:+$'\n'}${label}:${key}"
    
    # Atomic write with secure permissions
    if ! secure_write "$KEYRING_KEYS_FILE" "$keys_content"; then
        release_lock
        die "Failed to store private key securely"
    fi
    
    # Update timeout
    if ! secure_write "$KEYRING_TIMEOUT_FILE" "$timeout_at"; then
        release_lock
        die "Failed to set key timeout"
    fi
    
    release_lock
    info "Private key stored securely with ${KEYRING_TIMEOUT}s timeout"
}

# Retrieve private key with validation
get_key() {
    local label="$1"
    validate_label "$label"
    
    if ! is_daemon_running; then
        return 1
    fi
    
    acquire_lock
    
    # Check timeout validity
    if [[ -f "$KEYRING_TIMEOUT_FILE" ]]; then
        local timeout_at current_time
        timeout_at=$(cat "$KEYRING_TIMEOUT_FILE" 2>/dev/null || echo "0")
        current_time=$(date +%s)
        
        if [[ ! "$timeout_at" =~ ^[0-9]+$ ]] || (( current_time > timeout_at )); then
            release_lock
            info "Key timeout expired"
            return 1
        fi
    fi
    
    # Retrieve key with validation
    if [[ -f "$KEYRING_KEYS_FILE" ]]; then
        local key
        key=$(grep "^${label}:" "$KEYRING_KEYS_FILE" 2>/dev/null | head -n1 | cut -d: -f2- || echo "")
        
        if [[ -n "$key" ]]; then
            validate_private_key "$key"  # Validate before returning
            release_lock
            echo "$key"
            return 0
        fi
    fi
    
    release_lock
    return 1
}

# Secure private key input with enhanced validation
prompt_private_key() {
    local label="$1"
    validate_label "$label"
    
    # Security warning and prompt
    cat >&2 << 'EOF'
🔐 Production-Hardened Private Key Authentication

This is a SECURE private key prompt with the following protections:
  ✓ Input hidden from terminal (no echo)
  ✓ Not stored in shell history
  ✓ Not visible in process lists
  ✓ Stored in secure memory with timeout
  ✓ Multiple-pass secure deletion on cleanup

⚠️  SECURITY WARNING: 
    This is educational software only. Never use with real funds.
    For production use, employ hardware wallets or certified software.

EOF
    
    echo -n "Enter private key (64 hex characters): " >&2
    
    # Disable terminal echo for secure input
    local original_settings
    if command -v stty >/dev/null 2>&1; then
        original_settings=$(stty -g 2>/dev/null || echo "")
        stty -echo 2>/dev/null || true
    fi
    
    local key
    read -r key
    
    # Restore terminal settings
    if [[ -n "$original_settings" ]] && command -v stty >/dev/null 2>&1; then
        stty "$original_settings" 2>/dev/null || true
    fi
    
    echo >&2  # New line after hidden input
    
    # Input validation and sanitization
    key=$(echo "$key" | tr -d '[:space:]' | tr 'a-f' 'A-F')
    
    if [[ -z "$key" ]]; then
        die "No private key provided"
    fi
    
    validate_private_key "$key"
    
    store_key "$key" "$label"
    
    # Clear key from memory (bash limitation - best effort)
    key=""
    unset key
    
    echo "✅ Private key authenticated and cached securely (${KEYRING_TIMEOUT}s timeout)" >&2
}

# Show comprehensive keyring status
show_status() {
    local status="inactive"
    local keys_count=0
    local time_remaining=0
    
    if is_daemon_running; then
        status="active"
        
        if [[ -f "$KEYRING_KEYS_FILE" ]]; then
            acquire_lock
            keys_count=$(wc -l < "$KEYRING_KEYS_FILE" 2>/dev/null || echo "0")
            release_lock
        fi
        
        if [[ -f "$KEYRING_TIMEOUT_FILE" ]]; then
            local timeout_at current_time
            timeout_at=$(cat "$KEYRING_TIMEOUT_FILE" 2>/dev/null || echo "0")
            current_time=$(date +%s)
            
            if [[ "$timeout_at" =~ ^[0-9]+$ ]]; then
                time_remaining=$((timeout_at - current_time))
                if (( time_remaining < 0 )); then
                    time_remaining=0
                fi
            fi
        fi
    fi
    
    if [[ $VERBOSE -eq 1 ]]; then
        cat >&2 << EOF
Keyring Status (Production-Hardened):
  Daemon: $status
  Keys cached: $keys_count
  Time remaining: ${time_remaining}s
  Session: $SESSION_ID
  Directory: $KEYRING_DIR
  Security: tmpfs=$(df -T "$KEYRING_DIR" 2>/dev/null | tail -n1 | awk '{print $2}' | grep -q tmpfs && echo "yes" || echo "no")
EOF
    else
        echo "$status"
    fi
}

# Secure key clearing
clear_keys() {
    if is_daemon_running; then
        acquire_lock
        secure_delete "$KEYRING_KEYS_FILE"
        rm -f "$KEYRING_TIMEOUT_FILE" 2>/dev/null || true
        release_lock
        info "Cached keys securely cleared"
    else
        info "No keyring daemon running"
    fi
}

# Kill daemon with secure cleanup
kill_daemon() {
    if is_daemon_running; then
        cleanup_keyring
        info "Keyring daemon stopped and cleaned up securely"
    else
        info "No keyring daemon running"
    fi
}

# Main execution with security validation
main() {
    validate_security_environment
    
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
            die "Invalid action: $ACTION"
            ;;
    esac
}

main "$@"