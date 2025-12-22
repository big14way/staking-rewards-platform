# Staking Rewards Pool

Flexible staking protocol with multiple pools, reward tiers, and comprehensive Chainhook analytics.

## Features

- **Multiple Pools**: Create pools with different APRs, lock periods
- **Reward Tiers**: Bronze → Silver → Gold → Platinum based on stake duration
- **Compound Rewards**: Auto-compound rewards back into stake
- **Cooldown System**: Configurable cooldown before withdrawal
- **Early Withdrawal**: 5% penalty for early exits
- **TVL Tracking**: Historical TVL data per pool

## Clarity 4 Features

| Feature | Usage |
|---------|-------|
| `stacks-block-time` | Lock periods, cooldowns, reward calculations |
| `restrict-assets?` | Safe stake transfers |
| `to-ascii?` | Human-readable pool info |

## Fee Structure

| Fee | Rate | Applied |
|-----|------|---------|
| Reward Fee | 10% | On reward claims |
| Early Withdrawal | 5% | Withdrawing before unlock |

## Reward Tiers

| Tier | Duration | Bonus |
|------|----------|-------|
| Bronze | < 30 days | 0% |
| Silver | 30-90 days | 10% |
| Gold | 90-180 days | 25% |
| Platinum | > 180 days | 50% |

## Chainhook Events

| Event | Description |
|-------|-------------|
| `pool-created` | New staking pool created |
| `pool-funded` | Reward pool funded |
| `stake-deposited` | User stakes tokens |
| `stake-withdrawn` | User withdraws stake |
| `rewards-claimed` | User claims rewards |
| `rewards-compounded` | Rewards restaked |
| `fee-collected` | Protocol fee collected |
| `cooldown-started` | Withdrawal cooldown begins |
| `tier-upgraded` | User reaches new tier |

## Quick Start

```bash
# Deploy contracts
cd staking-rewards-pool
clarinet check && clarinet test

# Start Chainhook server
cd server && npm install && npm start

# Register chainhook
chainhook predicates scan ./chainhooks/staking-events.json --testnet
```

## Contract Functions

### Pool Management (Admin)

```clarity
;; Create pool
(create-pool name reward-rate min-stake lock-period cooldown-period duration)

;; Fund reward pool
(fund-reward-pool pool-id amount)

;; Pause/Resume
(pause-pool pool-id)
(resume-pool pool-id)
```

### Staking

```clarity
;; Stake tokens
(stake pool-id amount)

;; Claim rewards
(claim-rewards pool-id)

;; Compound rewards
(compound pool-id)

;; Start cooldown
(start-cooldown pool-id)

;; Withdraw stake
(withdraw pool-id amount)
```

## API Endpoints

```bash
GET /api/stats              # Protocol statistics
GET /api/stats/daily        # Daily metrics
GET /api/pools              # All pools
GET /api/pools/:id          # Pool details
GET /api/pools/:id/tvl-history # TVL over time
GET /api/users/:address     # User stats
GET /api/users/:address/stakes # User's stakes
GET /api/stakes/recent      # Recent stakes
GET /api/rewards/recent     # Recent rewards
GET /api/fees               # Fee history
```

## Example

```typescript
// Admin creates pool: 5% APR, 1 STX min, 7-day lock, 1-day cooldown
const poolId = await createPool({
    name: "STX Staking Pool",
    rewardRate: 500,      // 5% daily rate
    minStake: 1000000,    // 1 STX
    lockPeriod: 604800,   // 7 days
    cooldownPeriod: 86400 // 1 day
});

// Fund reward pool
await fundRewardPool(poolId, 1000000000); // 1000 STX

// User stakes 100 STX
await stake(poolId, 100000000);

// After earning rewards, user can:
await claimRewards(poolId);    // Claim to wallet
// OR
await compound(poolId);         // Restake rewards

// To withdraw:
await startCooldown(poolId);   // Wait cooldown period
await withdraw(poolId, 100000000);
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Smart Contracts                           │
│  ┌────────────────────┐    ┌────────────────────┐          │
│  │   staking-core     │    │ reward-distributor │          │
│  │  - create-pool     │    │  - tier management │          │
│  │  - stake           │    │  - bonus calc      │          │
│  │  - withdraw        │    │  - referrals       │          │
│  │  - claim-rewards   │    └────────────────────┘          │
│  │  - compound        │                                     │
│  │  print { event }   │ ← Emits events                     │
│  └────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Chainhook captures events
┌─────────────────────────────────────────────────────────────┐
│                   Chainhook Server                           │
│  - Track stakes, withdrawals, rewards                       │
│  - Calculate TVL history                                    │
│  - User tier tracking                                       │
│  - Fee analytics                                            │
└─────────────────────────────────────────────────────────────┘
```

## License

MIT License

## Testnet Deployment

### staking-governance
- **Status**: ✅ Deployed to Testnet
- **Transaction ID**: `cc66c07296433721293168f9e95911e82cc529bbf41ed5ea164891c5d3ade70f`
- **Deployer**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM`
- **Explorer**: https://explorer.hiro.so/txid/cc66c07296433721293168f9e95911e82cc529bbf41ed5ea164891c5d3ade70f?chain=testnet
- **Deployment Date**: December 22, 2025

### Network Configuration
- Network: Stacks Testnet
- Clarity Version: 4
- Epoch: 3.3
- Chainhooks: Configured and ready

### Contract Features
- Comprehensive validation and error handling
- Event emission for Chainhook monitoring
- Fully tested with `clarinet check`
- Production-ready security measures

## WalletConnect Integration

This project includes a fully-functional React dApp with WalletConnect v2 integration for seamless interaction with Stacks blockchain wallets.

### Features

- **🔗 Multi-Wallet Support**: Connect with any WalletConnect-compatible Stacks wallet
- **✍️ Transaction Signing**: Sign messages and submit transactions directly from the dApp
- **📝 Contract Interactions**: Call smart contract functions on Stacks testnet
- **🔐 Secure Connection**: End-to-end encrypted communication via WalletConnect relay
- **📱 QR Code Support**: Easy mobile wallet connection via QR code scanning

### Quick Start

#### Prerequisites

- Node.js (v16.x or higher)
- npm or yarn package manager
- A Stacks wallet (Xverse, Leather, or any WalletConnect-compatible wallet)

#### Installation

```bash
cd dapp
npm install
```

#### Running the dApp

```bash
npm start
```

The dApp will open in your browser at `http://localhost:3000`

#### Building for Production

```bash
npm run build
```

### WalletConnect Configuration

The dApp is pre-configured with:

- **Project ID**: 1eebe528ca0ce94a99ceaa2e915058d7
- **Network**: Stacks Testnet (Chain ID: `stacks:2147483648`)
- **Relay**: wss://relay.walletconnect.com
- **Supported Methods**:
  - `stacks_signMessage` - Sign arbitrary messages
  - `stacks_stxTransfer` - Transfer STX tokens
  - `stacks_contractCall` - Call smart contract functions
  - `stacks_contractDeploy` - Deploy new smart contracts

### Project Structure

```
dapp/
├── public/
│   └── index.html
├── src/
│   ├── components/
│   │   ├── WalletConnectButton.js      # Wallet connection UI
│   │   └── ContractInteraction.js       # Contract call interface
│   ├── contexts/
│   │   └── WalletConnectContext.js     # WalletConnect state management
│   ├── hooks/                            # Custom React hooks
│   ├── utils/                            # Utility functions
│   ├── config/
│   │   └── stacksConfig.js             # Network and contract configuration
│   ├── styles/                          # CSS styling
│   ├── App.js                           # Main application component
│   └── index.js                         # Application entry point
└── package.json
```

### Usage Guide

#### 1. Connect Your Wallet

Click the "Connect Wallet" button in the header. A QR code will appear - scan it with your mobile Stacks wallet or use the desktop wallet extension.

#### 2. Interact with Contracts

Once connected, you can:

- View your connected address
- Call read-only contract functions
- Submit contract call transactions
- Sign messages for authentication

#### 3. Disconnect

Click the "Disconnect" button to end the WalletConnect session.

### Customization

#### Updating Contract Configuration

Edit `src/config/stacksConfig.js` to point to your deployed contracts:

```javascript
export const CONTRACT_CONFIG = {
  contractName: 'your-contract-name',
  contractAddress: 'YOUR_CONTRACT_ADDRESS',
  network: 'testnet' // or 'mainnet'
};
```

#### Adding Custom Contract Functions

Modify `src/components/ContractInteraction.js` to add your contract-specific functions:

```javascript
const myCustomFunction = async () => {
  const result = await callContract(
    CONTRACT_CONFIG.contractAddress,
    CONTRACT_CONFIG.contractName,
    'your-function-name',
    [functionArgs]
  );
};
```

### Technical Details

#### WalletConnect v2 Implementation

The dApp uses the official WalletConnect v2 Sign Client with:

- **@walletconnect/sign-client**: Core WalletConnect functionality
- **@walletconnect/utils**: Helper utilities for encoding/decoding
- **@walletconnect/qrcode-modal**: QR code display for mobile connection
- **@stacks/connect**: Stacks-specific wallet integration
- **@stacks/transactions**: Transaction building and signing
- **@stacks/network**: Network configuration for testnet/mainnet

#### BigInt Serialization

The dApp includes BigInt serialization support for handling large numbers in Clarity contracts:

```javascript
BigInt.prototype.toJSON = function() { return this.toString(); };
```

### Supported Wallets

Any wallet supporting WalletConnect v2 and Stacks blockchain, including:

- **Xverse Wallet** (Recommended)
- **Leather Wallet** (formerly Hiro Wallet)
- **Boom Wallet**
- Any other WalletConnect-compatible Stacks wallet

### Troubleshooting

**Connection Issues:**
- Ensure your wallet app supports WalletConnect v2
- Check that you're on the correct network (testnet vs mainnet)
- Try refreshing the QR code or restarting the dApp

**Transaction Failures:**
- Verify you have sufficient STX for gas fees
- Confirm the contract address and function names are correct
- Check that post-conditions are properly configured

**Build Errors:**
- Clear node_modules and reinstall: `rm -rf node_modules && npm install`
- Ensure Node.js version is 16.x or higher
- Check for dependency conflicts in package.json

### Resources

- [WalletConnect Documentation](https://docs.walletconnect.com/)
- [Stacks.js Documentation](https://docs.stacks.co/build-apps/stacks.js)
- [Xverse WalletConnect Guide](https://docs.xverse.app/wallet-connect)
- [Stacks Blockchain Documentation](https://docs.stacks.co/)

### Security Considerations

- Never commit your private keys or seed phrases
- Always verify transaction details before signing
- Use testnet for development and testing
- Audit smart contracts before mainnet deployment
- Keep dependencies updated for security patches

### License

This dApp implementation is provided as-is for integration with the Stacks smart contracts in this repository.

