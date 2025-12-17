import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

const ONE_DAY = 86400;
const ONE_WEEK = 604800;

Clarinet.test({
    name: "Admin can create staking pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-core', 'create-pool', [
                types.ascii("STX Staking Pool"),
                types.uint(500),      // 5% daily APR (500 bps)
                types.uint(1000000),  // 1 STX min stake
                types.uint(ONE_WEEK), // 7 day lock
                types.uint(ONE_DAY),  // 1 day cooldown
                types.none()          // No end date
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Non-admin cannot create pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-core', 'create-pool', [
                types.ascii("Fake Pool"),
                types.uint(500),
                types.uint(1000000),
                types.uint(ONE_WEEK),
                types.uint(ONE_DAY),
                types.none()
            ], user.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(23001); // ERR_NOT_AUTHORIZED
    }
});

Clarinet.test({
    name: "User can stake in pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const staker = accounts.get('wallet_1')!;
        
        // Create pool
        chain.mineBlock([
            Tx.contractCall('staking-core', 'create-pool', [
                types.ascii("STX Pool"),
                types.uint(500),
                types.uint(1000000),
                types.uint(ONE_WEEK),
                types.uint(ONE_DAY),
                types.none()
            ], deployer.address)
        ]);
        
        // Stake
        let block = chain.mineBlock([
            Tx.contractCall('staking-core', 'stake', [
                types.uint(1),
                types.uint(10000000) // 10 STX
            ], staker.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(10000000);
    }
});

Clarinet.test({
    name: "Cannot stake below minimum",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const staker = accounts.get('wallet_1')!;
        
        chain.mineBlock([
            Tx.contractCall('staking-core', 'create-pool', [
                types.ascii("STX Pool"),
                types.uint(500),
                types.uint(10000000), // 10 STX minimum
                types.uint(ONE_WEEK),
                types.uint(ONE_DAY),
                types.none()
            ], deployer.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-core', 'stake', [
                types.uint(1),
                types.uint(5000000) // 5 STX - below minimum
            ], staker.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(23003); // ERR_INVALID_AMOUNT
    }
});

Clarinet.test({
    name: "Reward fee is 10%",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let fee = chain.callReadOnlyFn(
            'staking-core',
            'calculate-reward-fee',
            [types.uint(100000000)], // 100 STX rewards
            user.address
        );
        
        assertEquals(fee.result, 'u10000000'); // 10 STX fee
    }
});

Clarinet.test({
    name: "Early withdrawal penalty is 5%",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let penalty = chain.callReadOnlyFn(
            'staking-core',
            'calculate-early-withdrawal-fee',
            [types.uint(100000000)], // 100 STX
            user.address
        );
        
        assertEquals(penalty.result, 'u5000000'); // 5 STX penalty
    }
});

Clarinet.test({
    name: "Get protocol stats",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let stats = chain.callReadOnlyFn(
            'staking-core',
            'get-protocol-stats',
            [],
            user.address
        );
        
        const data = stats.result.expectTuple();
        assertEquals(data['total-pools'], types.uint(0));
        assertEquals(data['total-staked'], types.uint(0));
    }
});

Clarinet.test({
    name: "Admin can pause and resume pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        // Create pool
        chain.mineBlock([
            Tx.contractCall('staking-core', 'create-pool', [
                types.ascii("STX Pool"),
                types.uint(500),
                types.uint(1000000),
                types.uint(ONE_WEEK),
                types.uint(ONE_DAY),
                types.none()
            ], deployer.address)
        ]);
        
        // Pause
        let block1 = chain.mineBlock([
            Tx.contractCall('staking-core', 'pause-pool', [
                types.uint(1)
            ], deployer.address)
        ]);
        block1.receipts[0].result.expectOk().expectBool(true);
        
        // Resume
        let block2 = chain.mineBlock([
            Tx.contractCall('staking-core', 'resume-pool', [
                types.uint(1)
            ], deployer.address)
        ]);
        block2.receipts[0].result.expectOk().expectBool(true);
    }
});

Clarinet.test({
    name: "Tier calculation based on duration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        // Bronze (< 30 days)
        let tier0 = chain.callReadOnlyFn('reward-distributor', 'get-tier-for-duration', [types.uint(ONE_WEEK)], user.address);
        assertEquals(tier0.result, 'u0');
        
        // Silver (30-90 days)
        let tier1 = chain.callReadOnlyFn('reward-distributor', 'get-tier-for-duration', [types.uint(ONE_DAY * 45)], user.address);
        assertEquals(tier1.result, 'u1');
        
        // Gold (90-180 days)
        let tier2 = chain.callReadOnlyFn('reward-distributor', 'get-tier-for-duration', [types.uint(ONE_DAY * 120)], user.address);
        assertEquals(tier2.result, 'u2');
        
        // Platinum (> 180 days)
        let tier3 = chain.callReadOnlyFn('reward-distributor', 'get-tier-for-duration', [types.uint(ONE_DAY * 200)], user.address);
        assertEquals(tier3.result, 'u3');
    }
});
