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
