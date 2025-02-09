# Bridge Setup Guide

This guide explains how to set up cross-chain bridges for the CAPYAI token ecosystem.

## Bridge Architecture

```
EVM Chains (ETH, BNB, Polygon, Base)
├── LayerZero Protocol
├── Trusted Remote Setup
└── Gas Estimation

Solana
├── Wormhole Protocol
└── Token Bridge Program

Cosmos
├── Axelar Protocol
└── IBC Channels
```

## Prerequisites

1. Deploy tokens on each chain first
2. Update `config/bridge_config.json` with deployed addresses
3. Have enough native tokens for gas fees on each chain

## Setup Steps

### 1. EVM Chains (LayerZero)

```bash
# Set up all LayerZero connections
npx hardhat run scripts/setup_bridges.js --network ethereum
npx hardhat run scripts/setup_bridges.js --network bnb
npx hardhat run scripts/setup_bridges.js --network polygon
npx hardhat run scripts/setup_bridges.js --network base
```

### 2. Solana (Wormhole)

The Solana token is pre-configured with Wormhole integration. Verify:
- Core Bridge: `worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth`
- Token Bridge: `wormDTUJ6AWPNvk59vGQbDvGJmqbDTdgWgAqcLBCgUb`

### 3. Cosmos (Axelar)

The Cosmos token uses Axelar for cross-chain transfers. Verify:
- Gateway Contract
- Gas Service Contract
- Channel Connections

## Bridge Fees

1. LayerZero: ~0.1-0.3% of transfer amount
2. Wormhole: Fixed 0.001 SOL per transfer
3. Axelar: Variable based on destination chain

## Security Notes

1. Always test with small amounts first
2. Monitor bridge transactions
3. Keep bridge configuration up to date
4. Use recommended gas limits

## Troubleshooting

1. If LayerZero transfer fails:
   - Check trusted remote setup
   - Verify gas limits
   - Ensure sufficient native tokens

2. If Wormhole transfer fails:
   - Check VAA (Verified Action Approval)
   - Verify guardian signatures
   - Check relayer status

3. If Axelar transfer fails:
   - Check IBC channel status
   - Verify gas payments
   - Check destination chain status

## Bridge Limits

Default limits per transfer:
- Maximum: 1,000,000 CAPYAI
- Minimum: 100 CAPYAI
- Tax: 2% on all transfers

## Support

For bridge-related issues:
1. LayerZero: https://layerzero.network/
2. Wormhole: https://wormhole.com/
3. Axelar: https://axelar.network/
