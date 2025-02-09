# Bridge Testing Guide

This guide provides step-by-step instructions for testing cross-chain bridges in the CAPYAI ecosystem.

## Test Environment Setup

```bash
# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your RPC URLs and private keys
```

## 1. LayerZero Bridge Tests (EVM ↔️ EVM)

### Test Script
```javascript
// scripts/test/layerzero.js
const amount = ethers.utils.parseEther("1000");

// BNB -> ETH
await bnbToken.bridgeOut(
    ethChainId,
    ethRecipient,
    amount,
    { value: ethers.utils.parseEther("0.1") } // BNB for gas
);

// Check receipt on ETH
await ethToken.balanceOf(ethRecipient);
```

### Test Cases
1. Small Transfer (100 CAPYAI)
2. Medium Transfer (10,000 CAPYAI)
3. Max Transfer (1,000,000 CAPYAI)
4. Invalid Transfer (> 1,000,000 CAPYAI)

## 2. Wormhole Bridge Tests (Solana ↔️ EVM)

### Test Script
```javascript
// scripts/test/wormhole.js
const amount = new BN("1000000000"); // 1000 CAPYAI

// Solana -> ETH
await solanaToken.bridge_out(
    ethDestination,
    amount,
    "ethereum"
);

// Check VAA
const vaa = await wormhole.getVAA(tx.signature);
```

### Test Cases
1. Solana -> ETH Transfer
2. ETH -> Solana Transfer
3. Failed VAA Generation
4. Retry Failed Transfer

## 3. Axelar Bridge Tests (Cosmos ↔️ EVM)

### Test Script
```javascript
// scripts/test/axelar.js
const amount = "1000000"; // 1000 CAPYAI

// Cosmos -> ETH
await cosmosToken.BridgeTransfer(
    { destination_chain: "ethereum",
      destination_address: ethRecipient,
      amount }
);
```

### Test Cases
1. Cosmos -> ETH Transfer
2. ETH -> Cosmos Transfer
3. IBC Channel Tests
4. Gas Payment Tests

## Monitoring Tests

```bash
# Start bridge monitor
node scripts/monitor_bridges.js

# Run test transfers
npm run test:bridges
```

## Common Test Scenarios

### 1. Basic Transfer Test
```bash
# 1. Start with 1000 CAPYAI on BNB
# 2. Bridge to ETH
# 3. Verify receipt (should be 980 after 2% tax)
# 4. Bridge back to BNB
# 5. Final balance should be ~960.4 CAPYAI
```

### 2. Multi-Chain Route Test
```bash
# Test route: BNB -> ETH -> Solana -> Cosmos -> BNB
# Starting amount: 10,000 CAPYAI
# Expected final amount: ~9,233 CAPYAI (after fees)
```

### 3. Stress Test
```bash
# 1. Send 10 simultaneous transfers
# 2. Mix of different chains
# 3. Monitor completion times
# 4. Check for any failed transfers
```

## Error Testing

### 1. Insufficient Gas
```bash
# Try bridging without enough gas fees
# Verify proper error handling
```

### 2. Network Issues
```bash
# Simulate network interruption during transfer
# Test recovery process
```

### 3. Invalid Destinations
```bash
# Test transfers to invalid addresses
# Verify proper validation
```

## Security Tests

### 1. Bridge Limits
```bash
# Test maximum transfer limit
# Test minimum transfer requirement
# Test tax calculations
```

### 2. Authorization
```bash
# Test unauthorized bridge calls
# Test paused bridge functionality
```

## Performance Metrics

Track these metrics during testing:
1. Transfer completion time
2. Gas costs per transfer
3. Success rate percentage
4. Error recovery time

## Test Results Template

```markdown
## Bridge Test Results
Date: YYYY-MM-DD
Version: x.x.x

1. Transfer Success Rate: XX%
2. Average Completion Time: XX minutes
3. Gas Costs (average):
   - ETH: XX ETH
   - BNB: XX BNB
   - SOL: XX SOL
4. Failed Transfers: XX
5. Error Recovery Success: XX%
```

## Emergency Procedures

1. Bridge Pause
```bash
# How to pause bridges in emergency
await bridge.pause();
```

2. Fund Recovery
```bash
# How to recover stuck funds
await bridge.recoverStuckTokens();
```

## Monitoring During Tests

1. Run monitoring script:
```bash
node scripts/monitor_bridges.js
```

2. Watch for:
- Transfer initiation
- VAA generation
- Destination chain confirmation
- Final receipt
- Any errors or delays

## After Testing

1. Generate test report
2. Update bridge parameters if needed
3. Document any issues found
4. Update monitoring thresholds

Remember to test on testnets first before mainnet!
