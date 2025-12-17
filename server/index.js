/**
 * Staking Rewards Pool Chainhook Event Server
 * Handles events from Hiro Chainhooks for the Staking Protocol
 */

const express = require('express');
const cors = require('cors');
const Database = require('better-sqlite3');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3004;
const AUTH_TOKEN = process.env.AUTH_TOKEN || 'YOUR_AUTH_TOKEN';

const db = new Database('staking_events.db');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS pools (
    pool_id INTEGER PRIMARY KEY,
    name TEXT,
    reward_rate INTEGER,
    min_stake INTEGER,
    lock_period INTEGER,
    total_staked INTEGER DEFAULT 0,
    total_rewards_paid INTEGER DEFAULT 0,
    staker_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active',
    created_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS stakes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pool_id INTEGER,
    staker TEXT,
    amount INTEGER,
    unlock_time INTEGER,
    staked_at INTEGER,
    is_new_staker INTEGER,
    block_height INTEGER,
    tx_id TEXT
  );

  CREATE TABLE IF NOT EXISTS withdrawals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pool_id INTEGER,
    staker TEXT,
    amount INTEGER,
    penalty INTEGER,
    net_amount INTEGER,
    is_early INTEGER,
    timestamp INTEGER
  );

  CREATE TABLE IF NOT EXISTS rewards (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pool_id INTEGER,
    staker TEXT,
    gross_rewards INTEGER,
    fee INTEGER,
    net_rewards INTEGER,
    is_compound INTEGER DEFAULT 0,
    timestamp INTEGER
  );

  CREATE TABLE IF NOT EXISTS users (
    address TEXT PRIMARY KEY,
    total_staked INTEGER DEFAULT 0,
    total_rewards INTEGER DEFAULT 0,
    total_fees INTEGER DEFAULT 0,
    pools_joined INTEGER DEFAULT 0,
    tier TEXT DEFAULT 'Bronze',
    first_stake INTEGER,
    last_activity INTEGER
  );

  CREATE TABLE IF NOT EXISTS fees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pool_id INTEGER,
    fee_type TEXT,
    amount INTEGER,
    staker TEXT,
    timestamp INTEGER
  );

  CREATE TABLE IF NOT EXISTS daily_stats (
    date TEXT PRIMARY KEY,
    stakes_count INTEGER DEFAULT 0,
    stake_volume INTEGER DEFAULT 0,
    withdrawals_count INTEGER DEFAULT 0,
    withdrawal_volume INTEGER DEFAULT 0,
    rewards_claimed INTEGER DEFAULT 0,
    fees_collected INTEGER DEFAULT 0,
    new_stakers INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS pool_tvl_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pool_id INTEGER,
    tvl INTEGER,
    staker_count INTEGER,
    timestamp INTEGER
  );
`);

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const authMiddleware = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${AUTH_TOKEN}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};

const extractEventData = (payload) => {
  const events = [];
  if (payload.apply && Array.isArray(payload.apply)) {
    for (const block of payload.apply) {
      const blockHeight = block.block_identifier?.index;
      if (block.transactions && Array.isArray(block.transactions)) {
        for (const tx of block.transactions) {
          const txId = tx.transaction_identifier?.hash;
          if (tx.metadata?.receipt?.events) {
            for (const event of tx.metadata.receipt.events) {
              if (event.type === 'SmartContractEvent' || event.type === 'print_event') {
                const printData = event.data?.value || event.contract_event?.value;
                if (printData) events.push({ data: printData, blockHeight, txId });
              }
            }
          }
        }
      }
    }
  }
  return events;
};

const updateDailyStats = (date, field, increment = 1) => {
  const existing = db.prepare('SELECT * FROM daily_stats WHERE date = ?').get(date);
  if (existing) {
    db.prepare(`UPDATE daily_stats SET ${field} = ${field} + ? WHERE date = ?`).run(increment, date);
  } else {
    db.prepare(`INSERT INTO daily_stats (date, ${field}) VALUES (?, ?)`).run(date, increment);
  }
};

const updateUser = (address, updates) => {
  const timestamp = Math.floor(Date.now() / 1000);
  const existing = db.prepare('SELECT * FROM users WHERE address = ?').get(address);
  
  if (existing) {
    const sets = Object.entries(updates).map(([k, v]) => `${k} = ${k} + ${v}`).join(', ');
    db.prepare(`UPDATE users SET ${sets}, last_activity = ? WHERE address = ?`).run(timestamp, address);
  } else {
    db.prepare(`INSERT INTO users (address, total_staked, total_rewards, total_fees, pools_joined, first_stake, last_activity) VALUES (?, ?, ?, ?, ?, ?, ?)`)
      .run(address, updates.total_staked || 0, updates.total_rewards || 0, updates.total_fees || 0, updates.pools_joined || 0, timestamp, timestamp);
  }
};

const recordTVL = (poolId) => {
  const pool = db.prepare('SELECT total_staked, staker_count FROM pools WHERE pool_id = ?').get(poolId);
  if (pool) {
    db.prepare('INSERT INTO pool_tvl_history (pool_id, tvl, staker_count, timestamp) VALUES (?, ?, ?, ?)')
      .run(poolId, pool.total_staked, pool.staker_count, Math.floor(Date.now() / 1000));
  }
};

const processEvent = (eventData, blockHeight, txId) => {
  const today = new Date().toISOString().split('T')[0];
  const timestamp = eventData.timestamp || Math.floor(Date.now() / 1000);

  switch (eventData.event) {
    case 'pool-created':
      db.prepare(`INSERT INTO pools (pool_id, name, reward_rate, min_stake, lock_period, created_at) VALUES (?, ?, ?, ?, ?, ?)`)
        .run(eventData['pool-id'], eventData.name, eventData['reward-rate'], eventData['min-stake'], eventData['lock-period'], timestamp);
      console.log(`🏊 Pool created: ${eventData.name} (${eventData['reward-rate']} bps APR)`);
      break;

    case 'pool-funded':
      console.log(`💰 Pool #${eventData['pool-id']} funded: ${eventData.amount}`);
      break;

    case 'stake-deposited':
      db.prepare(`INSERT INTO stakes (pool_id, staker, amount, unlock_time, staked_at, is_new_staker, block_height, tx_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(eventData['pool-id'], eventData.staker, eventData.amount, eventData['unlock-time'], timestamp, eventData['is-new-staker'] ? 1 : 0, blockHeight, txId);
      
      // Update pool TVL
      db.prepare(`UPDATE pools SET total_staked = total_staked + ?, staker_count = staker_count + ? WHERE pool_id = ?`)
        .run(eventData.amount, eventData['is-new-staker'] ? 1 : 0, eventData['pool-id']);
      
      updateDailyStats(today, 'stakes_count');
      updateDailyStats(today, 'stake_volume', eventData.amount);
      if (eventData['is-new-staker']) updateDailyStats(today, 'new_stakers');
      
      updateUser(eventData.staker, { total_staked: eventData.amount, pools_joined: eventData['is-new-staker'] ? 1 : 0 });
      recordTVL(eventData['pool-id']);
      
      console.log(`📥 Stake: ${eventData.amount} to Pool #${eventData['pool-id']} by ${eventData.staker.slice(0, 10)}...`);
      break;

    case 'stake-withdrawn':
      db.prepare(`INSERT INTO withdrawals (pool_id, staker, amount, penalty, net_amount, is_early, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)`)
        .run(eventData['pool-id'], eventData.staker, eventData.amount, eventData.penalty, eventData['net-amount'], eventData['is-early-withdrawal'] ? 1 : 0, timestamp);
      
      db.prepare(`UPDATE pools SET total_staked = total_staked - ? WHERE pool_id = ?`)
        .run(eventData.amount, eventData['pool-id']);
      
      if (eventData['remaining-stake'] === 0) {
        db.prepare(`UPDATE pools SET staker_count = staker_count - 1 WHERE pool_id = ?`).run(eventData['pool-id']);
      }
      
      updateDailyStats(today, 'withdrawals_count');
      updateDailyStats(today, 'withdrawal_volume', eventData.amount);
      recordTVL(eventData['pool-id']);
      
      console.log(`📤 Withdrawal: ${eventData['net-amount']} from Pool #${eventData['pool-id']}${eventData.penalty > 0 ? ` (penalty: ${eventData.penalty})` : ''}`);
      break;

    case 'rewards-claimed':
      db.prepare(`INSERT INTO rewards (pool_id, staker, gross_rewards, fee, net_rewards, timestamp) VALUES (?, ?, ?, ?, ?, ?)`)
        .run(eventData['pool-id'], eventData.staker, eventData['gross-rewards'], eventData.fee, eventData['net-rewards'], timestamp);
      
      updateDailyStats(today, 'rewards_claimed', eventData['net-rewards']);
      updateUser(eventData.staker, { total_rewards: eventData['net-rewards'], total_fees: eventData.fee });
      
      console.log(`🎁 Rewards claimed: ${eventData['net-rewards']} (fee: ${eventData.fee})`);
      break;

    case 'rewards-compounded':
      db.prepare(`INSERT INTO rewards (pool_id, staker, gross_rewards, fee, net_rewards, is_compound, timestamp) VALUES (?, ?, ?, ?, ?, 1, ?)`)
        .run(eventData['pool-id'], eventData.staker, eventData['rewards-compounded'] + eventData.fee, eventData.fee, eventData['rewards-compounded'], timestamp);
      
      db.prepare(`UPDATE pools SET total_staked = total_staked + ? WHERE pool_id = ?`)
        .run(eventData['rewards-compounded'], eventData['pool-id']);
      
      recordTVL(eventData['pool-id']);
      console.log(`🔄 Compounded: ${eventData['rewards-compounded']} in Pool #${eventData['pool-id']}`);
      break;

    case 'fee-collected':
      db.prepare(`INSERT INTO fees (pool_id, fee_type, amount, staker, timestamp) VALUES (?, ?, ?, ?, ?)`)
        .run(eventData['pool-id'], eventData['fee-type'], eventData.amount, eventData.staker, timestamp);
      updateDailyStats(today, 'fees_collected', eventData.amount);
      console.log(`💵 Fee: ${eventData.amount} (${eventData['fee-type']})`);
      break;

    case 'tier-upgraded':
      db.prepare(`UPDATE users SET tier = ? WHERE address = ?`).run(eventData['tier-name'], eventData.user);
      console.log(`⬆️ Tier upgrade: ${eventData.user.slice(0, 10)}... → ${eventData['tier-name']}`);
      break;

    case 'cooldown-started':
      console.log(`⏳ Cooldown started for ${eventData.staker.slice(0, 10)}... in Pool #${eventData['pool-id']}`);
      break;

    case 'pool-paused':
      db.prepare(`UPDATE pools SET status = 'paused' WHERE pool_id = ?`).run(eventData['pool-id']);
      console.log(`⏸️ Pool #${eventData['pool-id']} paused`);
      break;

    case 'pool-resumed':
      db.prepare(`UPDATE pools SET status = 'active' WHERE pool_id = ?`).run(eventData['pool-id']);
      console.log(`▶️ Pool #${eventData['pool-id']} resumed`);
      break;
  }
};

// API Routes
app.post('/api/staking-events', authMiddleware, (req, res) => {
  try {
    const events = extractEventData(req.body);
    for (const { data, blockHeight, txId } of events) {
      if (data && data.event) processEvent(data, blockHeight, txId);
    }
    res.status(200).json({ success: true, processed: events.length });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Analytics endpoints
app.get('/api/stats', (req, res) => {
  res.json({
    totalPools: db.prepare('SELECT COUNT(*) as c FROM pools').get().c,
    activePools: db.prepare("SELECT COUNT(*) as c FROM pools WHERE status = 'active'").get().c,
    totalStaked: db.prepare('SELECT COALESCE(SUM(total_staked), 0) as s FROM pools').get().s,
    totalStakers: db.prepare('SELECT COUNT(*) as c FROM users').get().c,
    totalRewardsPaid: db.prepare('SELECT COALESCE(SUM(net_rewards), 0) as s FROM rewards').get().s,
    totalFees: db.prepare('SELECT COALESCE(SUM(amount), 0) as s FROM fees').get().s
  });
});

app.get('/api/stats/daily', (req, res) => {
  const days = parseInt(req.query.days) || 30;
  res.json(db.prepare('SELECT * FROM daily_stats ORDER BY date DESC LIMIT ?').all(days));
});

app.get('/api/pools', (req, res) => {
  res.json(db.prepare('SELECT * FROM pools ORDER BY created_at DESC').all());
});

app.get('/api/pools/:id', (req, res) => {
  const pool = db.prepare('SELECT * FROM pools WHERE pool_id = ?').get(req.params.id);
  if (!pool) return res.status(404).json({ error: 'Pool not found' });
  res.json(pool);
});

app.get('/api/pools/:id/tvl-history', (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  res.json(db.prepare('SELECT * FROM pool_tvl_history WHERE pool_id = ? ORDER BY timestamp DESC LIMIT ?').all(req.params.id, limit));
});

app.get('/api/users/:address', (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE address = ?').get(req.params.address);
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json(user);
});

app.get('/api/users/:address/stakes', (req, res) => {
  res.json(db.prepare('SELECT * FROM stakes WHERE staker = ? ORDER BY staked_at DESC').all(req.params.address));
});

app.get('/api/stakes/recent', (req, res) => {
  const limit = parseInt(req.query.limit) || 20;
  res.json(db.prepare('SELECT * FROM stakes ORDER BY staked_at DESC LIMIT ?').all(limit));
});

app.get('/api/rewards/recent', (req, res) => {
  const limit = parseInt(req.query.limit) || 20;
  res.json(db.prepare('SELECT * FROM rewards ORDER BY timestamp DESC LIMIT ?').all(limit));
});

app.get('/api/fees', (req, res) => {
  const limit = parseInt(req.query.limit) || 50;
  res.json(db.prepare('SELECT * FROM fees ORDER BY timestamp DESC LIMIT ?').all(limit));
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.listen(PORT, () => {
  console.log(`🏦 Staking Chainhook Server on port ${PORT}`);
});

module.exports = app;
