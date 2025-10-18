# 🖥️ CLI Wallet Architecture - Unix Philosophy Style

## 📐 CORE PRINCIPLE: Single Responsibility Commands

Each command does ONE thing, outputs JSON, and can be piped together.

---

## 🎯 COMMAND LIST

```bash
# Wallet Management
salawallet init                    # Generate new wallet
salawallet import                  # Import from seed phrase
salawallet export-seed             # Export seed phrase (secure)
salawallet addresses               # List all addresses (all chains)

# Balance & Info
salawallet balance [chain]         # Get balance
salawallet address [chain]         # Get receiving address
salawallet networks                # List supported chains

# Transactions
salawallet send                    # Send transaction
salawallet status <tx_hash>        # Check tx status
salawallet history [chain]         # Transaction history
salawallet estimate-fee            # Estimate transaction fee

# Advanced
salawallet sign                    # Sign message/transaction
salawallet broadcast               # Broadcast raw transaction
salawallet watch                   # Watch address (read-only)
```

---

## 📂 RECOMMENDED FILE STRUCTURE

```
salawallet-cli/
├── package.json
├── bin/
│   └── salawallet                 # Main entry point (dispatcher)
├── src/
│   ├── core/
│   │   ├── wallet-manager.js      # WDK wrapper
│   │   ├── storage.js             # Secure key storage
│   │   └── config.js              # Config management
│   ├── commands/
│   │   ├── init.js                # Generate wallet
│   │   ├── import.js              # Import wallet
│   │   ├── balance.js             # Get balance
│   │   ├── address.js             # Get address
│   │   ├── send.js                # Send transaction
│   │   ├── status.js              # Transaction status
│   │   ├── history.js             # Transaction history
│   │   ├── addresses.js           # List all addresses
│   │   ├── networks.js            # List networks
│   │   ├── estimate-fee.js        # Fee estimation
│   │   └── export-seed.js         # Export seed
│   └── utils/
│       ├── output.js              # JSON formatter
│       ├── input.js               # Stdin reader
│       └── validation.js          # Input validation
└── .salawallet/                   # User data directory
    ├── config.json                # User config
    └── keystore/                  # Encrypted keys
```

---

## 🔧 COMMAND DESIGN PATTERNS

### Pattern 1: Standard Output (JSON)
```bash
salawallet balance ethereum
# Output:
{
  "chain": "ethereum",
  "address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  "balance": "1.234567890123456789",
  "decimals": 18,
  "symbol": "ETH",
  "usd_value": "2469.14"
}
```

### Pattern 2: Input from Stdin OR Args
```bash
# From args
salawallet send --chain ethereum --to 0xABC... --amount 0.1

# From stdin (pipeable)
echo '{"chain":"ethereum","to":"0xABC...","amount":"0.1"}' | salawallet send

# From file
cat transaction.json | salawallet send
```

### Pattern 3: Chaining Commands
```bash
# Get address, then check balance
salawallet address ethereum | jq -r '.address' | xargs -I {} salawallet balance ethereum

# Send and immediately check status
salawallet send --chain ethereum --to 0xABC... --amount 0.1 | \
  jq -r '.tx_hash' | \
  xargs salawallet status

# Watch for balance changes
watch -n 5 'salawallet balance bitcoin'
```

---

## 📋 DETAILED COMMAND SPECIFICATIONS

### 1. **`salawallet init`** - Generate New Wallet

**Purpose:** Create new wallet with seed phrase

**Input:** None (or optional passphrase)

**Output:**
```json
{
  "status": "success",
  "seed_phrase": "word1 word2 word3 ... word12",
  "addresses": {
    "bitcoin": "bc1q...",
    "ethereum": "0x...",
    "polygon": "0x...",
    "arbitrum": "0x...",
    "ton": "EQ..."
  },
  "warning": "SAVE YOUR SEED PHRASE SECURELY"
}
```

**Usage:**
```bash
# Generate and save seed to file
salawallet init > wallet-backup.json

# Generate with passphrase
salawallet init --passphrase "my-secure-passphrase"

# Show only seed phrase
salawallet init | jq -r '.seed_phrase'
```

---

### 2. **`salawallet import`** - Import Existing Wallet

**Purpose:** Import wallet from seed phrase

**Input:** Seed phrase (stdin or arg)

**Output:**
```json
{
  "status": "success",
  "addresses": {
    "bitcoin": "bc1q...",
    "ethereum": "0x..."
  }
}
```

**Usage:**
```bash
# Interactive
salawallet import
# Enter seed phrase: word1 word2 word3...

# From stdin
echo "word1 word2 word3 ... word12" | salawallet import

# From file
cat seed.txt | salawallet import

# From args
salawallet import --seed "word1 word2 ... word12"
```

---

### 3. **`salawallet address`** - Get Receiving Address

**Purpose:** Get address for specific chain

**Input:** Chain name

**Output:**
```json
{
  "chain": "ethereum",
  "address": "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  "qr_code_url": "data:image/png;base64,..."
}
```

**Usage:**
```bash
# Get Ethereum address
salawallet address ethereum

# Just the address string
salawallet address ethereum | jq -r '.address'

# Copy to clipboard (macOS)
salawallet address bitcoin | jq -r '.address' | pbcopy

# Generate QR code
salawallet address ethereum | jq -r '.qr_code_url' > qr.png
```

---

### 4. **`salawallet balance`** - Check Balance

**Purpose:** Get balance for one or all chains

**Input:** Chain name (optional, defaults to all)

**Output:**
```json
{
  "chain": "ethereum",
  "balance": "1.234567890123456789",
  "symbol": "ETH",
  "usd_value": "2469.14",
  "tokens": [
    {
      "symbol": "USDT",
      "balance": "1000.000000",
      "contract": "0xdac17f958d2ee523a2206206994597c13d831ec7",
      "usd_value": "1000.00"
    }
  ]
}
```

**Usage:**
```bash
# Single chain
salawallet balance ethereum

# All chains
salawallet balance

# Just native balance value
salawallet balance ethereum | jq -r '.balance'

# Total USD value
salawallet balance | jq '[.[] | .usd_value] | add'

# Watch balance (refresh every 10s)
watch -n 10 'salawallet balance bitcoin | jq -r ".balance"'
```

---

### 5. **`salawallet send`** - Send Transaction

**Purpose:** Send tokens/coins

**Input:** Chain, recipient, amount

**Output:**
```json
{
  "status": "success",
  "tx_hash": "0xabc123...",
  "chain": "ethereum",
  "from": "0x742d...",
  "to": "0x123...",
  "amount": "0.1",
  "fee": "0.00021",
  "explorer_url": "https://etherscan.io/tx/0xabc123..."
}
```

**Usage:**
```bash
# Send ETH
salawallet send \
  --chain ethereum \
  --to 0x123... \
  --amount 0.1

# Send USDT token
salawallet send \
  --chain ethereum \
  --token 0xdac17f958d2ee523a2206206994597c13d831ec7 \
  --to 0x123... \
  --amount 100

# From JSON stdin
echo '{
  "chain": "bitcoin",
  "to": "bc1q...",
  "amount": "0.001"
}' | salawallet send

# Send all balance
salawallet balance ethereum | \
  jq '{chain: .chain, to: "0x123...", amount: .balance}' | \
  salawallet send

# Send and get tx hash only
salawallet send --chain bitcoin --to bc1q... --amount 0.01 | \
  jq -r '.tx_hash'
```

---

### 6. **`salawallet status`** - Check Transaction Status

**Purpose:** Check transaction confirmation status

**Input:** Transaction hash

**Output:**
```json
{
  "tx_hash": "0xabc123...",
  "status": "confirmed",
  "confirmations": 12,
  "block_number": 18234567,
  "timestamp": "2025-10-18T10:30:00Z",
  "from": "0x742d...",
  "to": "0x123...",
  "amount": "0.1",
  "fee": "0.00021"
}
```

**Usage:**
```bash
# Check status
salawallet status 0xabc123...

# Just status
salawallet status 0xabc123... | jq -r '.status'

# Wait for confirmation
while [ "$(salawallet status 0xabc... | jq -r '.status')" != "confirmed" ]; do
  echo "Waiting..."
  sleep 10
done
echo "Confirmed!"

# Chain send and check status
salawallet send --chain ethereum --to 0x123... --amount 0.1 | \
  jq -r '.tx_hash' | \
  xargs salawallet status
```

---

### 7. **`salawallet history`** - Transaction History

**Purpose:** List past transactions

**Input:** Chain (optional), limit

**Output:**
```json
{
  "chain": "ethereum",
  "transactions": [
    {
      "tx_hash": "0xabc...",
      "type": "send",
      "amount": "0.1",
      "to": "0x123...",
      "timestamp": "2025-10-18T10:30:00Z",
      "status": "confirmed"
    },
    {
      "tx_hash": "0xdef...",
      "type": "receive",
      "amount": "1.5",
      "from": "0x456...",
      "timestamp": "2025-10-17T15:20:00Z",
      "status": "confirmed"
    }
  ]
}
```

**Usage:**
```bash
# Recent 10 transactions
salawallet history ethereum --limit 10

# All chains
salawallet history

# Filter by type
salawallet history ethereum | jq '.transactions[] | select(.type == "send")'

# Get CSV format
salawallet history bitcoin | \
  jq -r '.transactions[] | [.timestamp, .type, .amount, .tx_hash] | @csv'

# Total sent
salawallet history ethereum | \
  jq '[.transactions[] | select(.type == "send") | .amount | tonumber] | add'
```

---

### 8. **`salawallet addresses`** - List All Addresses

**Purpose:** Show all addresses for all chains

**Output:**
```json
{
  "bitcoin": "bc1q...",
  "ethereum": "0x...",
  "polygon": "0x...",
  "arbitrum": "0x...",
  "ton": "EQ..."
}
```

**Usage:**
```bash
# List all
salawallet addresses

# Pretty format
salawallet addresses | jq -r 'to_entries[] | "\(.key): \(.value)"'

# Get specific chain
salawallet addresses | jq -r '.ethereum'
```

---

### 9. **`salawallet networks`** - List Supported Networks

**Purpose:** Show available chains and their status

**Output:**
```json
{
  "networks": [
    {
      "name": "ethereum",
      "enabled": true,
      "rpc_status": "online",
      "block_height": 18234567
    },
    {
      "name": "bitcoin",
      "enabled": true,
      "rpc_status": "online",
      "block_height": 815234
    }
  ]
}
```

**Usage:**
```bash
# List networks
salawallet networks

# Check if network is online
salawallet networks | jq '.networks[] | select(.name == "ethereum") | .rpc_status'
```

---

### 10. **`salawallet estimate-fee`** - Estimate Transaction Fee

**Purpose:** Get fee estimate before sending

**Input:** Chain, amount

**Output:**
```json
{
  "chain": "ethereum",
  "fee_estimate": "0.00021",
  "fee_symbol": "ETH",
  "fee_usd": "0.42",
  "gas_price": "25",
  "gas_limit": "21000"
}
```

**Usage:**
```bash
# Estimate fee
salawallet estimate-fee --chain ethereum --amount 0.1

# Get just the fee value
salawallet estimate-fee --chain bitcoin --amount 0.01 | jq -r '.fee_estimate'

# Calculate total cost
echo '{
  "chain": "ethereum",
  "to": "0x123...",
  "amount": "0.1"
}' | salawallet estimate-fee | \
  jq '{amount: .amount, fee: .fee_estimate, total: (.amount + .fee_estimate)}'
```

---

### 11. **`salawallet export-seed`** - Export Seed Phrase

**Purpose:** Export seed phrase (requires confirmation)

**Output:**
```json
{
  "seed_phrase": "word1 word2 word3 ... word12",
  "warning": "KEEP THIS SAFE AND PRIVATE"
}
```

**Usage:**
```bash
# Export (requires password confirmation)
salawallet export-seed

# Save to encrypted file
salawallet export-seed | gpg --encrypt > seed-backup.gpg
```

---

## 🔗 PIPING EXAMPLES (Real-World Use Cases)

### Example 1: Send and Track
```bash
# Send transaction and continuously monitor status
salawallet send --chain ethereum --to 0x123... --amount 0.5 | \
  jq -r '.tx_hash' | \
  xargs -I {} sh -c 'while true; do salawallet status {} | jq -r ".status"; sleep 10; done'
```

### Example 2: Batch Balance Check
```bash
# Check all balances and export to CSV
salawallet addresses | \
  jq -r 'to_entries[] | .key' | \
  xargs -I {} sh -c 'salawallet balance {} | jq -r "[.chain, .balance, .usd_value] | @csv"'
```

### Example 3: Conditional Send
```bash
# Send only if balance is above threshold
BALANCE=$(salawallet balance ethereum | jq -r '.balance | tonumber')
if (( $(echo "$BALANCE > 1.0" | bc -l) )); then
  salawallet send --chain ethereum --to 0x123... --amount 0.5
else
  echo "Insufficient balance"
fi
```

### Example 4: Transaction Log
```bash
# Generate daily transaction report
salawallet history ethereum | \
  jq '.transactions[] | select(.timestamp > "2025-10-18")' | \
  jq -s '.' > daily-report.json
```

### Example 5: Multi-Chain Balance Dashboard
```bash
# Create simple balance dashboard
watch -n 30 '
echo "=== WALLET BALANCES ==="
for chain in bitcoin ethereum polygon arbitrum; do
  echo -n "$chain: "
  salawallet balance $chain | jq -r ".balance + \" \" + .symbol + \" ($\" + .usd_value + \")\""
done
'
```

---

## 🏗️ IMPLEMENTATION APPROACH

### Core Module (`src/core/wallet-manager.js`)
```javascript
import { WDKService } from '@tetherto/wdk'; // Hypothetical import

class WalletManager {
  constructor() {
    this.wdk = null;
    this.storage = new SecureStorage();
  }

  async init() {
    const seed = await this.storage.getSeed();
    this.wdk = new WDKService(seed);
  }

  async getBalance(chain) {
    return await this.wdk.getBalance(chain);
  }

  async send(chain, to, amount) {
    return await this.wdk.send(chain, to, amount);
  }

  // ... other methods
}

export default WalletManager;
```

### Command Template (`src/commands/balance.js`)
```javascript
import WalletManager from '../core/wallet-manager.js';
import { outputJSON, outputError } from '../utils/output.js';
import { readStdin } from '../utils/input.js';

export async function balanceCommand(args) {
  try {
    const wallet = new WalletManager();
    await wallet.init();

    // Get chain from args or stdin
    const chain = args.chain || (await readStdin()).chain;
    
    const balance = await wallet.getBalance(chain);
    
    outputJSON({
      chain,
      balance: balance.amount,
      symbol: balance.symbol,
      usd_value: balance.usdValue,
      tokens: balance.tokens
    });
  } catch (error) {
    outputError(error.message);
    process.exit(1);
  }
}
```

### Main Entry Point (`bin/salawallet`)
```javascript
#!/usr/bin/env node

import { program } from 'commander';
import { balanceCommand } from '../src/commands/balance.js';
import { sendCommand } from '../src/commands/send.js';
// ... import other commands

program
  .name('salawallet')
  .description('CLI wallet built on Tether WDK')
  .version('1.0.0');

program
  .command('balance [chain]')
  .description('Get balance for a chain')
  .action(balanceCommand);

program
  .command('send')
  .description('Send transaction')
  .option('--chain <chain>', 'blockchain')
  .option('--to <address>', 'recipient address')
  .option('--amount <amount>', 'amount to send')
  .action(sendCommand);

// ... other commands

program.parse();
```

---

## 🎯 BENEFITS OF THIS ARCHITECTURE

✅ **Unix Philosophy** - Each command does one thing well
✅ **Composable** - Commands can be piped and chained
✅ **Scriptable** - Easy to automate with shell scripts
✅ **Testable** - Each command can be tested independently
✅ **Extensible** - Add new commands without touching existing ones
✅ **JSON Output** - Machine-readable, works with `jq`
✅ **Consistent** - All commands follow same input/output pattern

---

Want me to:
1. Create the full implementation code for any specific command?
2. Show how to integrate with the WDK SDK specifically?
3. Add more advanced piping examples?
4. Create a makefile/build script?