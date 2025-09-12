# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bitcoin CLI Wallet Toolkit - an educational implementation of BIP39 mnemonic generation and BIP32 hierarchical deterministic wallet key derivation using Bash scripts and standard Unix tools. The codebase is designed for **educational purposes only** and should never be used with real Bitcoin funds.

## Core Architecture

The toolkit follows a Unix pipeline architecture with five main components that can be chained together:

```
entropy → indices → words → seed/keys → public_keys
```

### Pipeline Components

1. **`random.sh`** - Entropy generation and checksum calculation
2. **`twelvenums.sh`** - Converts hex entropy to 12 BIP39 word indices (0-2047)
3. **`numtoword.sh`** - Converts numeric indices to BIP39 mnemonic words using `english.txt`
4. **`privatekey.sh`** - Derives BIP32 master private keys from BIP39 mnemonics
5. **`public_key.sh`** - Generates Bitcoin public keys from secp256k1 private keys
6. **`address.sh`** - Generates Bitcoin addresses from public keys (P2PKH, P2SH, P2WPKH, etc.)
7. **`balance.sh`** - Checks Bitcoin address balances via public APIs
8. **`network.sh`** - Manages network selection (mainnet/testnet) for other commands
9. **`send.sh`** - Creates and broadcasts Bitcoin transactions (educational implementation)

### Supporting Files

- **`english.txt`** - Official BIP39 English wordlist (2048 words)
- **`man/`** - Comprehensive Unix manual pages for all scripts
- **`TODO.md`** - Development roadmap and planned features

## Development Commands

### Prerequisites Setup
```bash
# macOS
brew install openssl curl jq bc

# Ubuntu/Debian  
sudo apt-get install openssl xxd bc curl jq

# CentOS/RHEL
sudo yum install openssl xxd bc curl jq

# Make scripts executable
chmod +x *.sh
```

### Secure Private Key Management
The toolkit uses a secure keyring system (like sudo) to protect private keys:

```bash
# Authentication required for operations needing private keys
keyauth.sh                    # Authenticate (prompts securely, 60s timeout)
keyauth-secure.sh send-secure.sh from to amt   # Production secure auth

# Check authentication status
keyauth.sh -c                 # Check if authenticated
keyring.sh -a status          # Detailed keyring status

# Clear cached keys (security)
keyring.sh -a clear           # Clear before timeout
keyring.sh -a kill            # Stop daemon entirely
```

### Testing Individual Components
```bash
# Test entropy generation
./random.sh -q hex

# Test known entropy conversion
echo "00000000000000000000000000000000" | ./twelvenums.sh -q

# Test word lookup (should output "abandon")
echo "0" | ./numtoword.sh

# Test mnemonic validation
echo "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about" | ./privatekey.sh -q
```

### Complete Pipeline Testing
```bash
# Generate complete mnemonic (quiet mode)
./random.sh -q | ./twelvenums.sh -q | ./numtoword.sh

# Full key derivation chain with verbose output
./random.sh -v | ./twelvenums.sh -v | ./numtoword.sh | ./privatekey.sh -v

# Complete wallet generation pipeline
./random.sh -q | ./twelvenums.sh -q | ./numtoword.sh | ./privatekey.sh -q | head -2 | tail -1 | ./public_key.sh -q -f compressed | ./address.sh -q -n testnet

# Check balance of generated address
./random.sh -q | ./twelvenums.sh -q | ./numtoword.sh | ./privatekey.sh -q | head -2 | tail -1 | ./public_key.sh -q -f compressed | ./address.sh -q -n testnet | ./balance.sh -n testnet
```

### Network Management
```bash
# Check current network setting
./network.sh

# Switch to testnet
./network.sh -a set testnet

# Check network connectivity
./network.sh -a status

# Show detailed network info
./network.sh -v -a status
```

### Wallet Operations
```bash
# Check address balance on testnet
./balance.sh -n testnet -u sat tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh

# Generate testnet address from public key  
echo "02a1b2c3..." | ./address.sh -n testnet -t p2wpkh

# Send Bitcoin (secure authentication required)
keyauth-secure.sh send-secure.sh -n testnet -d -f 5 tb1qfrom... tb1qto... 50000
```

## Script Interface Standards

All scripts follow consistent Unix-style conventions:

### Universal Options
- **`-q`** - Quiet mode (suppress warnings, clean stdout for pipelines)
- **`-v`** - Verbose mode (detailed progress to stderr)
- **`-h`** - Help/usage information

### Input/Output Patterns
- **stdin/argument flexibility** - All scripts accept input via stdin or command line arguments
- **Clean stdout** - Pure data only (no formatting text when piped)
- **stderr messaging** - All warnings, progress, and errors go to stderr
- **TTY detection** - Interactive prompts only when terminal detected

### Pipeline Examples
```bash
# Interactive mode (prompts user)
./privatekey.sh

# Pipeline mode (reads from stdin)
echo "word1 word2 ... word12" | ./privatekey.sh -q

# Argument mode
./twelvenums.sh -q a1b2c3d4e5f678901234567890123456

# Network-aware commands
./balance.sh -n testnet tb1q...     # Explicit network
./balance.sh tb1q...                # Auto-detect from network.sh

# Multi-format output
./public_key.sh -f compressed private_key_hex
./address.sh -t p2wpkh -n testnet public_key_hex

# Secure private key operations (NO keys in CLI)
keyauth.sh                          # Authenticate once
./public_key.sh -f compressed       # Uses keyring (no CLI key needed)
keyauth-secure.sh send-secure.sh from to amount   # Production secure send
```

## Cryptographic Implementation

### Standards Compliance
- **BIP39** - Mnemonic code generation with proper checksum validation
- **BIP32** - Hierarchical deterministic wallet key derivation
- **PBKDF2-HMAC-SHA512** - 2048 iterations for seed derivation
- **secp256k1** - Bitcoin's elliptic curve for public key generation

### Key Security Considerations
- OpenSSL 3.x required (not LibreSSL) for proper cryptographic operations
- Temporary files created with secure permissions (700)
- Proper cleanup handlers for interrupted operations
- Input validation for all cryptographic parameters
- Range validation for secp256k1 private keys

## Manual Pages

Install comprehensive man pages for detailed usage:
```bash
# User-specific installation
mkdir -p ~/.local/share/man/man1
cp man/man1/*.1 ~/.local/share/man/man1/
export MANPATH="$HOME/.local/share/man:$MANPATH"

# Usage
man random
man twelvenums  
man numtoword
man privatekey
```

## Development Workflow

### When Adding New Scripts
1. Follow the established input/output patterns (-q/-v/-h options)
2. Implement both stdin and argument input methods
3. Separate data output (stdout) from messages (stderr)
4. Add comprehensive error handling with proper exit codes
5. Create corresponding manual page in `man/man1/`
6. Update TODO.md with completion status

### Pipeline Debugging
```bash
# Use verbose mode to track data flow
./random.sh -v hex | ./twelvenums.sh -v | ./numtoword.sh

# Test individual components with known values
echo "a1b2c3d4e5f678901234567890123456" | ./twelvenums.sh -v
```

### Security Review Requirements
- All entropy generation must use cryptographically secure sources (OpenSSL)
- Private key material must never be logged or exposed in debug output
- Temporary files must be securely created and cleaned up
- Input validation must prevent buffer overflows and injection attacks
- **CRITICAL**: Private keys must NEVER appear in command line arguments (use keyring system)
- All keyring operations must be authenticated and time-limited
- Secure memory cleanup on process termination

## Wallet Management Features

### Production-Hardened Security System
**CRITICAL SECURITY**: Private keys are managed through production-grade secure components:

#### Core Security Components
- **`keyring-secure.sh`** - Production-hardened keyring daemon with defense in depth
- **`keyauth-secure.sh`** - Hardened authentication with comprehensive input validation  
- **`send-secure.sh`** - Secure transaction sender with multiple security layers

#### Advanced Security Features
**Memory Protection:**
- Shared memory storage (/dev/shm) when available
- Multiple-pass secure deletion (3 passes with random data)
- Memory clearing on timeout/exit with proper cleanup handlers

**Input Validation & Sanitization:**
- Comprehensive pattern matching for all inputs
- Buffer overflow prevention with strict length limits
- Command injection protection with argument sanitization
- Path traversal attack prevention

**Process Security:**
- Process isolation with controlled environment variables
- Resource limits to prevent resource exhaustion attacks
- Atomic file operations with exclusive locking
- Race condition prevention with proper synchronization

**Session Management:**
- Cryptographically secure session IDs (256-bit entropy)
- Configurable timeouts (1-300 seconds)
- Session isolation per user/process

#### Migration Path
For production environments:
- Use `keyauth-secure.sh` instead of `keyauth.sh`
- Use `send-secure.sh` instead of `send.sh`
- Use `keyring-secure.sh` instead of `keyring.sh`

Legacy versions remain for educational compatibility.

### Network Configuration
The toolkit supports both Bitcoin mainnet and testnet:
- **`network.sh`** manages global network settings stored in `~/.bitcoin-toolkit-config`
- Commands auto-detect network unless explicitly overridden with `-n` flag
- Environment variable `BITCOIN_NETWORK` takes precedence over config file

### Address Generation
Supports multiple address types:
- **P2PKH** - Pay to Public Key Hash (legacy addresses starting with 1/m)
- **P2SH** - Pay to Script Hash (addresses starting with 3/2) 
- **P2WPKH** - Pay to Witness Public Key Hash (SegWit bech32)
- **P2WSH** - Pay to Witness Script Hash (SegWit bech32)

### Balance Checking
Uses public APIs for balance queries:
- **Blockstream.info** (default) - Reliable, no rate limits for basic usage
- **BlockCypher** - Alternative API with higher rate limits
- **Blockchair** - Future implementation
- Returns balance in BTC or satoshis with `-u` flag

### Transaction Creation
Educational implementation includes:
- UTXO fetching and selection
- Fee estimation based on transaction size
- Address ownership verification
- Dry-run mode for safe testing (`-d` flag)
- Configurable fee rates in sat/byte

## Important Limitations

This is an **educational toolkit only**. For production Bitcoin applications:
- **Transaction broadcasting** - Educational placeholder only, not functional
- **Address derivation** - Uses simplified Base58/Bech32 encoding
- **UTXO selection** - Basic largest-first algorithm, not optimal
- **Fee estimation** - Rough approximation, not accurate for all transaction types
- **Security** - No secure memory handling for private keys
- Use established libraries like libsecp256k1, bitcoinjs, or hardware wallets
- Implement proper memory management for sensitive data
- Add formal security auditing and testing
- Use secure key storage mechanisms
- Implement proper random number generation validation