# Bitcoin CLI Wallet Toolkit

A command-line Bitcoin wallet toolkit for generating and managing Bitcoin private keys, mnemonics, and wallet functions. Built with Bash scripts following BIP39 and BIP32 standards.

> ⚠️ **SECURITY WARNING**: This toolkit is for educational and testing purposes only. Never use these scripts for real funds or production environments. Always use hardware wallets or certified software for actual Bitcoin storage.

## Features

### Current Implementation
- **Entropy Generation**: Generate cryptographically secure random entropy for wallet creation
- **Mnemonic Support**: Full BIP39 mnemonic phrase generation and validation (12/15/18/21/24 words)
- **Private Key Derivation**: BIP32 master private key generation from mnemonic seeds
- **Word Conversion**: Convert between numeric indices and BIP39 words
- **Checksum Validation**: Automatic checksum calculation and verification

### Planned Features
- Public key generation
- Bitcoin address derivation (Legacy, SegWit, Native SegWit)
- Transaction creation and signing
- UTXO management
- Multi-signature support
- Hardware wallet integration

## Installation

### Prerequisites
```bash
# macOS (Homebrew)
brew install openssl

# Ubuntu/Debian
sudo apt-get install openssl xxd bc

# CentOS/RHEL
sudo yum install openssl xxd bc
```

### Setup
```bash
git clone https://github.com/yourusername/bitcoin-cli-wallet
cd bitcoin-cli-wallet
chmod +x *.sh
```

## Quick Start

Generate a complete mnemonic phrase with a single command:

```
./random.sh | tail -1 | ./twelvenums.sh | ./numtoword.sh
```

This pipeline:
1. Generates random entropy using `random.sh`
2. Converts entropy to BIP39 indices with `twelvenums.sh`
3. Outputs the 12-word mnemonic phrase using `numtoword.sh`

**Example output:**
```
abandon ability able about above absent absorb abstract absurd abuse access accident
```

### Prerequisites
Make sure all scripts are executable:
```
chmod +x random.sh twelvenums.sh numtoword.sh
```

## Usage

### 1. Generate Entropy
Generate random entropy for mnemonic creation:

```bash
# Generate 128-bit entropy in hex format
./random.sh hex

# Generate entropy in binary format
./random.sh binary

# Calculate checksum for existing entropy
./random.sh checksum a1b2c3d4e5f678901234567890123456
```

### 2. Convert Entropy to Mnemonic Indices
Convert hex entropy to BIP39 word indices:

```bash
echo 'a1b2c3d4e5f678901234567890123456' | ./twelvenums.sh
```

### 3. Convert Numbers to Words
Convert numeric indices to BIP39 words:

```bash
echo -e "123\n456\n789" | ./numtoword.sh
```

### 4. Generate Private Key from Mnemonic
Derive master private key from mnemonic phrase:

```bash
./privatekey.sh
# Enter your 12/15/18/21/24-word mnemonic when prompted
# Optionally enter a passphrase for additional security
```

## File Structure

```
├── english.txt          # BIP39 English wordlist (2048 words)
├── random.sh           # Entropy generation and checksum calculation
├── twelvenums.sh       # Entropy to mnemonic index conversion
├── numtoword.sh        # Index to word conversion
├── privatekey.sh       # Mnemonic to private key derivation
└── README.md           # This file
```

## Technical Details

### Standards Compliance
- **BIP39**: Mnemonic code for generating deterministic keys
- **BIP32**: Hierarchical Deterministic (HD) Wallets
- **PBKDF2**: Password-Based Key Derivation Function 2
- **HMAC-SHA512**: Hash-based Message Authentication Code

### Cryptographic Operations
- **Entropy**: 128-bit random generation using OpenSSL
- **Checksum**: First 4 bits of SHA-256 hash of entropy
- **Seed Derivation**: PBKDF2-HMAC-SHA512 with 2048 iterations
- **Master Key**: HMAC-SHA512 with "Bitcoin seed" as key

### Security Features
- Input validation for all parameters
- Proper entropy length verification
- BIP39 wordlist validation
- Checksum verification for data integrity

## Examples

### Complete Workflow
```bash
# 1. Generate entropy
ENTROPY=$(./random.sh hex | tail -1)
echo "Generated entropy: $ENTROPY"

# 2. Convert to indices
echo "$ENTROPY" | ./twelvenums.sh > indices.txt

# 3. Convert to mnemonic words
cat indices.txt | ./numtoword.sh > mnemonic.txt

# 4. Generate private key
./privatekey.sh
# Paste the mnemonic from mnemonic.txt when prompted
```

### Debug Mode
Enable verbose output for troubleshooting:
```bash
DEBUG=1 ./twelvenums.sh
```

## Development

### Testing
```bash
# Test with known entropy values
echo "00000000000000000000000000000000" | ./twelvenums.sh

# Verify word conversion
echo "0" | ./numtoword.sh  # Should output "abandon"
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Roadmap

- [ ] Public key generation from private keys
- [ ] Bitcoin address derivation (P2PKH, P2SH, P2WPKH, P2WSH)
- [ ] Transaction builder and signer
- [ ] UTXO management and coin selection
- [ ] Multi-signature wallet support
- [ ] Hardware wallet integration (Ledger, Trezor)
- [ ] Testnet support
- [ ] Fee estimation
- [ ] QR code generation for addresses

## Dependencies

- **OpenSSL 3.x**: Cryptographic operations
- **xxd**: Hex dump utility
- **bc**: Basic calculator for arbitrary precision arithmetic
- **awk**: Text processing
- **grep**: Pattern matching

## License

MIT License - see LICENSE file for details.

## Disclaimer

This software is provided "as is" without any warranty. The authors are not responsible for any loss of funds or security breaches. This toolkit is intended for educational purposes and should not be used with real Bitcoin funds.

## References

- [BIP39: Mnemonic code for generating deterministic keys](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [BIP32: Hierarchical Deterministic Wallets](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [Bitcoin Developer Documentation](https://developer.bitcoin.org/)
