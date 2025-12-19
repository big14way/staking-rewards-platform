;; staking-core.clar
;; Flexible Staking Protocol with Chainhook-trackable events
;; Uses Clarity 4 features: stacks-block-time, restrict-assets?, to-ascii?
;; Emits print events for: stake-deposited, stake-withdrawn, rewards-claimed, pool-created, fee-collected

(define-constant CONTRACT_OWNER tx-sender)
(define-data-var contract-principal principal tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u23001))
(define-constant ERR_POOL_NOT_FOUND (err u23002))
(define-constant ERR_INVALID_AMOUNT (err u23003))
(define-constant ERR_INSUFFICIENT_STAKE (err u23004))
(define-constant ERR_COOLDOWN_ACTIVE (err u23005))
(define-constant ERR_POOL_INACTIVE (err u23006))
(define-constant ERR_NO_REWARDS (err u23007))
(define-constant ERR_TIER_NOT_FOUND (err u23008))

;; Pool status
(define-constant POOL_ACTIVE u0)
(define-constant POOL_PAUSED u1)
(define-constant POOL_ENDED u2)

;; Time constants
(define-constant ONE_DAY u86400)
(define-constant ONE_WEEK u604800)

;; Protocol fee: 10% of rewards (1000 basis points)
(define-constant REWARD_FEE_BPS u1000)

;; Early withdrawal penalty: 5%
(define-constant EARLY_WITHDRAWAL_FEE_BPS u500)

;; Loyalty tiers
(define-constant TIER_BRONZE u0)
(define-constant TIER_SILVER u1)
(define-constant TIER_GOLD u2)
(define-constant TIER_PLATINUM u3)

;; Tier thresholds (in days of staking)
(define-constant TIER_SILVER_DAYS u30)
(define-constant TIER_GOLD_DAYS u90)
(define-constant TIER_PLATINUM_DAYS u180)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var pool-counter uint u0)
(define-data-var total-staked uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var total-stakers uint u0)
(define-data-var loyalty-enabled bool true)
(define-data-var total-tier-upgrades uint u0)

;; ========================================
;; Data Maps
;; ========================================

;; Staking pools
(define-map pools
    uint
    {
        name: (string-ascii 64),
        reward-rate: uint,
        min-stake: uint,
        lock-period: uint,
        cooldown-period: uint,
        total-staked: uint,
        total-rewards-paid: uint,
        staker-count: uint,
        created-at: uint,
        ends-at: (optional uint),
        status: uint,
        reward-pool-balance: uint
    }
)

;; User stakes per pool
(define-map stakes
    { pool-id: uint, staker: principal }
    {
        amount: uint,
        staked-at: uint,
        last-claim: uint,
        rewards-earned: uint,
        unlock-time: uint,
        cooldown-start: (optional uint)
    }
)

;; User overall statistics
(define-map user-stats
    principal
    {
        total-staked: uint,
        total-rewards-earned: uint,
        total-fees-paid: uint,
        pools-joined: uint,
        first-stake: uint,
        last-activity: uint
    }
)

;; Track unique stakers
(define-map registered-stakers principal bool)

;; Loyalty tiers
(define-map loyalty-tiers
    { pool-id: uint, staker: principal }
    {
        current-tier: uint,
        tier-since: uint,
        total-bonus-earned: uint,
        fee-discount-used: uint,
        last-tier-check: uint
    }
)

;; Tier benefits configuration
(define-map tier-benefits
    uint
    {
        name: (string-ascii 32),
        reward-bonus-bps: uint,
        fee-discount-bps: uint,
        min-days-staked: uint
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-current-time) stacks-block-time)

(define-read-only (get-pool (pool-id uint))
    (map-get? pools pool-id))

(define-read-only (get-stake (pool-id uint) (staker principal))
    (map-get? stakes { pool-id: pool-id, staker: staker }))

(define-read-only (get-user-stats (user principal))
    (map-get? user-stats user))

(define-read-only (calculate-reward-fee (rewards uint))
    (/ (* rewards REWARD_FEE_BPS) u10000))

(define-read-only (calculate-early-withdrawal-fee (amount uint))
    (/ (* amount EARLY_WITHDRAWAL_FEE_BPS) u10000))

;; Calculate pending rewards for a stake
(define-read-only (calculate-pending-rewards (pool-id uint) (staker principal))
    (match (map-get? stakes { pool-id: pool-id, staker: staker })
        stake (match (map-get? pools pool-id)
            pool (let
                (
                    (current-time stacks-block-time)
                    (time-staked (- current-time (get last-claim stake)))
                    (daily-rate (get reward-rate pool))
                    (stake-amount (get amount stake))
                    ;; rewards = (stake * rate * time) / (10000 * ONE_DAY)
                    (rewards (/ (* (* stake-amount daily-rate) time-staked) (* u10000 ONE_DAY)))
                )
                rewards)
            u0)
        u0))

;; Check if stake is unlocked
(define-read-only (is-stake-unlocked (pool-id uint) (staker principal))
    (match (map-get? stakes { pool-id: pool-id, staker: staker })
        stake (>= stacks-block-time (get unlock-time stake))
        false))

;; Check if cooldown is complete
(define-read-only (is-cooldown-complete (pool-id uint) (staker principal))
    (match (map-get? stakes { pool-id: pool-id, staker: staker })
        stake (match (get cooldown-start stake)
            cooldown-time (match (map-get? pools pool-id)
                pool (>= stacks-block-time (+ cooldown-time (get cooldown-period pool)))
                false)
            true) ;; No cooldown started means can withdraw
        false))

(define-read-only (get-protocol-stats)
    {
        total-pools: (var-get pool-counter),
        total-staked: (var-get total-staked),
        total-rewards: (var-get total-rewards-distributed),
        total-fees: (var-get total-fees-collected),
        total-stakers: (var-get total-stakers),
        loyalty-enabled: (var-get loyalty-enabled),
        total-tier-upgrades: (var-get total-tier-upgrades),
        current-time: stacks-block-time
    })

(define-read-only (get-loyalty-tier (pool-id uint) (staker principal))
    (map-get? loyalty-tiers { pool-id: pool-id, staker: staker }))

(define-read-only (get-tier-benefits (tier uint))
    (map-get? tier-benefits tier))

(define-private (get-tier-from-days (days-staked uint))
    (if (>= days-staked TIER_PLATINUM_DAYS)
        TIER_PLATINUM
        (if (>= days-staked TIER_GOLD_DAYS)
            TIER_GOLD
            (if (>= days-staked TIER_SILVER_DAYS)
                TIER_SILVER
                TIER_BRONZE))))

(define-read-only (calculate-current-tier (pool-id uint) (staker principal))
    (match (map-get? stakes { pool-id: pool-id, staker: staker })
        stake (let
            (
                (current-time stacks-block-time)
                (staked-at (get staked-at stake))
                (days-staked (/ (- current-time staked-at) ONE_DAY))
            )
            (get-tier-from-days days-staked))
        TIER_BRONZE))

(define-private (calculate-tier-bonus-private (base-rewards uint) (tier uint))
    (match (map-get? tier-benefits tier)
        benefits (/ (* base-rewards (get reward-bonus-bps benefits)) u10000)
        u0))

(define-private (calculate-tier-fee-discount-private (base-fee uint) (tier uint))
    (match (map-get? tier-benefits tier)
        benefits (/ (* base-fee (get fee-discount-bps benefits)) u10000)
        u0))

(define-read-only (calculate-tier-bonus (base-rewards uint) (tier uint))
    (calculate-tier-bonus-private base-rewards tier))

(define-read-only (calculate-tier-fee-discount (base-fee uint) (tier uint))
    (calculate-tier-fee-discount-private base-fee tier))

;; Generate pool info using to-ascii?
(define-read-only (generate-pool-info (pool-id uint))
    (match (map-get? pools pool-id)
        pool (let
            (
                (id-str (unwrap-panic (to-ascii? pool-id)))
                (staked-str (unwrap-panic (to-ascii? (get total-staked pool))))
                (stakers-str (unwrap-panic (to-ascii? (get staker-count pool))))
                (rate-str (unwrap-panic (to-ascii? (get reward-rate pool))))
            )
            (concat 
                (concat (concat "Pool #" id-str) (concat ": " (get name pool)))
                (concat (concat " | TVL: " staked-str)
                    (concat (concat " | Stakers: " stakers-str)
                        (concat " | APR: " (concat rate-str "bps"))))))
        "Pool not found"))

;; ========================================
;; Private Helper Functions
;; ========================================

(define-private (update-user-stats-stake (user principal) (amount uint))
    (let
        (
            (current-stats (default-to 
                { total-staked: u0, total-rewards-earned: u0, total-fees-paid: u0,
                  pools-joined: u0, first-stake: stacks-block-time, last-activity: u0 }
                (map-get? user-stats user)))
            (is-new-staker (is-none (map-get? registered-stakers user)))
        )
        ;; Register new staker
        (if is-new-staker
            (begin
                (map-set registered-stakers user true)
                (var-set total-stakers (+ (var-get total-stakers) u1)))
            true)
        ;; Update stats
        (map-set user-stats user (merge current-stats {
            total-staked: (+ (get total-staked current-stats) amount),
            last-activity: stacks-block-time
        }))))

;; ========================================
;; Public Functions - Pool Management
;; ========================================

;; Create a new staking pool
(define-public (create-pool
    (name (string-ascii 64))
    (reward-rate uint)
    (min-stake uint)
    (lock-period uint)
    (cooldown-period uint)
    (duration (optional uint)))
    (let
        (
            (pool-id (+ (var-get pool-counter) u1))
            (current-time stacks-block-time)
            (end-time (match duration
                d (some (+ current-time d))
                none))
        )
        ;; Only admin can create pools
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> reward-rate u0) ERR_INVALID_AMOUNT)
        
        ;; Create pool
        (map-set pools pool-id {
            name: name,
            reward-rate: reward-rate,
            min-stake: min-stake,
            lock-period: lock-period,
            cooldown-period: cooldown-period,
            total-staked: u0,
            total-rewards-paid: u0,
            staker-count: u0,
            created-at: current-time,
            ends-at: end-time,
            status: POOL_ACTIVE,
            reward-pool-balance: u0
        })
        
        (var-set pool-counter pool-id)
        
        ;; EMIT EVENT: pool-created
        (print {
            event: "pool-created",
            pool-id: pool-id,
            name: name,
            reward-rate: reward-rate,
            min-stake: min-stake,
            lock-period: lock-period,
            timestamp: current-time
        })
        
        (ok pool-id)))

;; Fund reward pool
(define-public (fund-reward-pool (pool-id uint) (amount uint))
    (let
        (
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (try! (stx-transfer? amount tx-sender (var-get contract-principal)))
        
        (map-set pools pool-id (merge pool {
            reward-pool-balance: (+ (get reward-pool-balance pool) amount)
        }))
        
        ;; EMIT EVENT: pool-funded
        (print {
            event: "pool-funded",
            pool-id: pool-id,
            amount: amount,
            new-balance: (+ (get reward-pool-balance pool) amount),
            timestamp: stacks-block-time
        })
        
        (ok true)))

;; ========================================
;; Public Functions - Staking
;; ========================================

;; Stake tokens
(define-public (stake (pool-id uint) (amount uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (current-time stacks-block-time)
            (existing-stake (map-get? stakes { pool-id: pool-id, staker: caller }))
            (is-new-staker (is-none existing-stake))
        )
        ;; Validations
        (asserts! (is-eq (get status pool) POOL_ACTIVE) ERR_POOL_INACTIVE)
        (asserts! (>= amount (get min-stake pool)) ERR_INVALID_AMOUNT)
        
        ;; Check pool hasn't ended
        (match (get ends-at pool)
            end-time (asserts! (< current-time end-time) ERR_POOL_INACTIVE)
            true)
        
        ;; Transfer stake
        (try! (stx-transfer? amount caller (var-get contract-principal)))

        ;; Update or create stake
        (if is-new-staker
            ;; New stake
            (begin
                (map-set stakes { pool-id: pool-id, staker: caller } {
                    amount: amount,
                    staked-at: current-time,
                    last-claim: current-time,
                    rewards-earned: u0,
                    unlock-time: (+ current-time (get lock-period pool)),
                    cooldown-start: none
                })
                ;; Update pool staker count
                (map-set pools pool-id (merge pool {
                    total-staked: (+ (get total-staked pool) amount),
                    staker-count: (+ (get staker-count pool) u1)
                })))
            ;; Add to existing stake
            (let ((stake (unwrap-panic existing-stake)))
                (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
                    amount: (+ (get amount stake) amount),
                    unlock-time: (+ current-time (get lock-period pool))
                }))
                (map-set pools pool-id (merge pool {
                    total-staked: (+ (get total-staked pool) amount)
                }))))

        ;; Update global stats
        (var-set total-staked (+ (var-get total-staked) amount))
        (update-user-stats-stake caller amount)

        ;; EMIT EVENT: stake-deposited
        (print {
            event: "stake-deposited",
            pool-id: pool-id,
            staker: caller,
            amount: amount,
            total-stake: (if is-new-staker amount (+ amount (get amount (unwrap-panic existing-stake)))),
            unlock-time: (+ current-time (get lock-period pool)),
            is-new-staker: is-new-staker,
            timestamp: current-time
        })

        (ok amount)))

;; Claim rewards
(define-public (claim-rewards (pool-id uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
            (pending-rewards (calculate-pending-rewards pool-id caller))
            (fee (calculate-reward-fee pending-rewards))
            (net-rewards (- pending-rewards fee))
        )
        ;; Validations
        (asserts! (> pending-rewards u0) ERR_NO_REWARDS)
        (asserts! (<= pending-rewards (get reward-pool-balance pool)) ERR_NO_REWARDS)
        
        ;; Transfer rewards to staker
        (try! (stx-transfer? net-rewards (var-get contract-principal) caller))

        ;; Transfer fee to protocol
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))
        
        ;; Update stake
        (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
            last-claim: current-time,
            rewards-earned: (+ (get rewards-earned stake) net-rewards)
        }))
        
        ;; Update pool
        (map-set pools pool-id (merge pool {
            total-rewards-paid: (+ (get total-rewards-paid pool) pending-rewards),
            reward-pool-balance: (- (get reward-pool-balance pool) pending-rewards)
        }))
        
        ;; Update global stats
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) net-rewards))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        
        ;; Update user stats
        (match (map-get? user-stats caller)
            stats (map-set user-stats caller (merge stats {
                total-rewards-earned: (+ (get total-rewards-earned stats) net-rewards),
                total-fees-paid: (+ (get total-fees-paid stats) fee),
                last-activity: current-time
            }))
            true)
        
        ;; EMIT EVENT: rewards-claimed
        (print {
            event: "rewards-claimed",
            pool-id: pool-id,
            staker: caller,
            gross-rewards: pending-rewards,
            fee: fee,
            net-rewards: net-rewards,
            timestamp: current-time
        })
        
        ;; EMIT EVENT: fee-collected
        (print {
            event: "fee-collected",
            pool-id: pool-id,
            fee-type: "reward",
            amount: fee,
            staker: caller,
            timestamp: current-time
        })
        
        (ok net-rewards)))

;; Start cooldown for withdrawal
(define-public (start-cooldown (pool-id uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
        )
        ;; Check stake is unlocked (lock period over)
        (asserts! (is-stake-unlocked pool-id caller) ERR_COOLDOWN_ACTIVE)
        ;; Check no cooldown already started
        (asserts! (is-none (get cooldown-start stake)) ERR_COOLDOWN_ACTIVE)
        
        (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
            cooldown-start: (some current-time)
        }))
        
        ;; EMIT EVENT: cooldown-started
        (print {
            event: "cooldown-started",
            pool-id: pool-id,
            staker: caller,
            cooldown-ends: (+ current-time (get cooldown-period pool)),
            timestamp: current-time
        })
        
        (ok true)))

;; Withdraw stake
(define-public (withdraw (pool-id uint) (amount uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
            (stake-amount (get amount stake))
            (is-early (not (is-stake-unlocked pool-id caller)))
            (penalty (if is-early (calculate-early-withdrawal-fee amount) u0))
            (net-amount (- amount penalty))
        )
        ;; Validations
        (asserts! (<= amount stake-amount) ERR_INSUFFICIENT_STAKE)
        (asserts! (or is-early (is-cooldown-complete pool-id caller)) ERR_COOLDOWN_ACTIVE)
        
        ;; Transfer to staker
        (try! (stx-transfer? net-amount (var-get contract-principal) caller))

        ;; Transfer penalty to protocol if applicable
        (if (> penalty u0)
            (try! (stx-transfer? penalty (var-get contract-principal) CONTRACT_OWNER))
            true)
        
        ;; Update stake
        (if (is-eq amount stake-amount)
            ;; Full withdrawal
            (begin
                (map-delete stakes { pool-id: pool-id, staker: caller })
                (map-set pools pool-id (merge pool {
                    total-staked: (- (get total-staked pool) amount),
                    staker-count: (- (get staker-count pool) u1)
                })))
            ;; Partial withdrawal
            (begin
                (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
                    amount: (- stake-amount amount),
                    cooldown-start: none
                }))
                (map-set pools pool-id (merge pool {
                    total-staked: (- (get total-staked pool) amount)
                }))))
        
        ;; Update global stats
        (var-set total-staked (- (var-get total-staked) amount))
        (if (> penalty u0)
            (var-set total-fees-collected (+ (var-get total-fees-collected) penalty))
            true)
        
        ;; EMIT EVENT: stake-withdrawn
        (print {
            event: "stake-withdrawn",
            pool-id: pool-id,
            staker: caller,
            amount: amount,
            penalty: penalty,
            net-amount: net-amount,
            is-early-withdrawal: is-early,
            remaining-stake: (- stake-amount amount),
            timestamp: current-time
        })
        
        ;; EMIT EVENT: fee-collected (if penalty)
        (if (> penalty u0)
            (print {
                event: "fee-collected",
                pool-id: pool-id,
                fee-type: "early-withdrawal",
                amount: penalty,
                staker: caller,
                timestamp: current-time
            })
            true)
        
        (ok net-amount)))

;; Compound rewards (claim and restake)
(define-public (compound (pool-id uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
            (pending-rewards (calculate-pending-rewards pool-id caller))
            (fee (calculate-reward-fee pending-rewards))
            (net-rewards (- pending-rewards fee))
        )
        ;; Validations
        (asserts! (is-eq (get status pool) POOL_ACTIVE) ERR_POOL_INACTIVE)
        (asserts! (> pending-rewards u0) ERR_NO_REWARDS)
        
        ;; Transfer fee only
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))
        
        ;; Add rewards to stake
        (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
            amount: (+ (get amount stake) net-rewards),
            last-claim: current-time,
            rewards-earned: (+ (get rewards-earned stake) net-rewards)
        }))
        
        ;; Update pool
        (map-set pools pool-id (merge pool {
            total-staked: (+ (get total-staked pool) net-rewards),
            total-rewards-paid: (+ (get total-rewards-paid pool) pending-rewards),
            reward-pool-balance: (- (get reward-pool-balance pool) pending-rewards)
        }))
        
        ;; Update global stats
        (var-set total-staked (+ (var-get total-staked) net-rewards))
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) net-rewards))
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
        
        ;; EMIT EVENT: rewards-compounded
        (print {
            event: "rewards-compounded",
            pool-id: pool-id,
            staker: caller,
            rewards-compounded: net-rewards,
            fee: fee,
            new-stake-amount: (+ (get amount stake) net-rewards),
            timestamp: current-time
        })
        
        (ok net-rewards)))

;; Initialize tier benefits (admin only)
(define-public (initialize-tier-benefits)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)

        (map-set tier-benefits TIER_BRONZE {
            name: "Bronze",
            reward-bonus-bps: u0,
            fee-discount-bps: u0,
            min-days-staked: u0
        })

        (map-set tier-benefits TIER_SILVER {
            name: "Silver",
            reward-bonus-bps: u500,
            fee-discount-bps: u2500,
            min-days-staked: TIER_SILVER_DAYS
        })

        (map-set tier-benefits TIER_GOLD {
            name: "Gold",
            reward-bonus-bps: u1000,
            fee-discount-bps: u5000,
            min-days-staked: TIER_GOLD_DAYS
        })

        (map-set tier-benefits TIER_PLATINUM {
            name: "Platinum",
            reward-bonus-bps: u2000,
            fee-discount-bps: u7500,
            min-days-staked: TIER_PLATINUM_DAYS
        })

        (print {
            event: "tier-benefits-initialized",
            timestamp: stacks-block-time
        })

        (ok true)))

;; Check and upgrade tier
(define-public (check-and-upgrade-tier (pool-id uint))
    (let
        (
            (caller tx-sender)
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
            (staked-at (get staked-at stake))
            (days-staked (/ (- current-time staked-at) ONE_DAY))
            (current-tier-level (get-tier-from-days days-staked))
            (existing-tier (map-get? loyalty-tiers { pool-id: pool-id, staker: caller }))
        )
        (asserts! (var-get loyalty-enabled) ERR_NOT_AUTHORIZED)

        (match existing-tier
            tier-data
                (if (> current-tier-level (get current-tier tier-data))
                    (begin
                        (map-set loyalty-tiers { pool-id: pool-id, staker: caller } (merge tier-data {
                            current-tier: current-tier-level,
                            tier-since: current-time,
                            last-tier-check: current-time
                        }))
                        (var-set total-tier-upgrades (+ (var-get total-tier-upgrades) u1))
                        (print {
                            event: "tier-upgraded",
                            pool-id: pool-id,
                            staker: caller,
                            old-tier: (get current-tier tier-data),
                            new-tier: current-tier-level,
                            timestamp: current-time
                        })
                        (ok true))
                    (begin
                        (map-set loyalty-tiers { pool-id: pool-id, staker: caller } (merge tier-data {
                            last-tier-check: current-time
                        }))
                        (ok false)))
            (begin
                (map-set loyalty-tiers { pool-id: pool-id, staker: caller } {
                    current-tier: current-tier-level,
                    tier-since: current-time,
                    total-bonus-earned: u0,
                    fee-discount-used: u0,
                    last-tier-check: current-time
                })
                (print {
                    event: "tier-initialized",
                    pool-id: pool-id,
                    staker: caller,
                    tier: current-tier-level,
                    timestamp: current-time
                })
                (ok true)))))

;; Claim rewards with tier bonuses
(define-public (claim-rewards-with-tier-bonus (pool-id uint))
    (let
        (
            (caller tx-sender)
            (pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND))
            (stake (unwrap! (map-get? stakes { pool-id: pool-id, staker: caller }) ERR_INSUFFICIENT_STAKE))
            (current-time stacks-block-time)
            (staked-at (get staked-at stake))
            (days-staked (/ (- current-time staked-at) ONE_DAY))
            (current-tier (get-tier-from-days days-staked))
            (time-staked (- current-time (get last-claim stake)))
            (daily-rate (get reward-rate pool))
            (stake-amount (get amount stake))
            (base-rewards (/ (* (* stake-amount daily-rate) time-staked) (* u10000 ONE_DAY)))
            (tier-bonus (if (var-get loyalty-enabled)
                           (calculate-tier-bonus-private base-rewards current-tier)
                           u0))
            (total-rewards (+ base-rewards tier-bonus))
            (base-fee (calculate-reward-fee total-rewards))
            (fee-discount (if (var-get loyalty-enabled)
                             (calculate-tier-fee-discount-private base-fee current-tier)
                             u0))
            (net-fee (- base-fee fee-discount))
            (net-rewards (- total-rewards net-fee))
            (tier-data (map-get? loyalty-tiers { pool-id: pool-id, staker: caller }))
        )
        ;; Validations
        (asserts! (> base-rewards u0) ERR_NO_REWARDS)
        (asserts! (<= total-rewards (get reward-pool-balance pool)) ERR_NO_REWARDS)

        ;; Transfer rewards to staker
        (try! (stx-transfer? net-rewards (var-get contract-principal) caller))

        ;; Transfer fee to protocol
        (try! (stx-transfer? net-fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Update stake
        (map-set stakes { pool-id: pool-id, staker: caller } (merge stake {
            last-claim: current-time,
            rewards-earned: (+ (get rewards-earned stake) net-rewards)
        }))

        ;; Update pool
        (map-set pools pool-id (merge pool {
            total-rewards-paid: (+ (get total-rewards-paid pool) total-rewards),
            reward-pool-balance: (- (get reward-pool-balance pool) total-rewards)
        }))

        ;; Update loyalty tier stats
        (match tier-data
            tier (map-set loyalty-tiers { pool-id: pool-id, staker: caller } (merge tier {
                total-bonus-earned: (+ (get total-bonus-earned tier) tier-bonus),
                fee-discount-used: (+ (get fee-discount-used tier) fee-discount)
            }))
            true)

        ;; Update global stats
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) net-rewards))
        (var-set total-fees-collected (+ (var-get total-fees-collected) net-fee))

        ;; Update user stats
        (match (map-get? user-stats caller)
            stats (map-set user-stats caller (merge stats {
                total-rewards-earned: (+ (get total-rewards-earned stats) net-rewards),
                total-fees-paid: (+ (get total-fees-paid stats) net-fee),
                last-activity: current-time
            }))
            true)

        ;; EMIT EVENT: rewards-claimed-with-bonus
        (print {
            event: "rewards-claimed-with-tier-bonus",
            pool-id: pool-id,
            staker: caller,
            base-rewards: base-rewards,
            tier-bonus: tier-bonus,
            total-rewards: total-rewards,
            tier: current-tier,
            base-fee: base-fee,
            fee-discount: fee-discount,
            net-fee: net-fee,
            net-rewards: net-rewards,
            timestamp: current-time
        })

        ;; EMIT EVENT: fee-collected
        (print {
            event: "fee-collected",
            pool-id: pool-id,
            fee-type: "reward-with-tier",
            amount: net-fee,
            discount-applied: fee-discount,
            staker: caller,
            timestamp: current-time
        })

        (ok { net-rewards: net-rewards, tier-bonus: tier-bonus, fee-discount: fee-discount })))

;; Toggle loyalty program
(define-public (toggle-loyalty-program)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set loyalty-enabled (not (var-get loyalty-enabled)))
        (print {
            event: "loyalty-program-toggled",
            enabled: (var-get loyalty-enabled),
            timestamp: stacks-block-time
        })
        (ok (var-get loyalty-enabled))))

;; ========================================
;; Admin Functions
;; ========================================

;; Pause pool
(define-public (pause-pool (pool-id uint))
    (let ((pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set pools pool-id (merge pool { status: POOL_PAUSED }))
        (print { event: "pool-paused", pool-id: pool-id, timestamp: stacks-block-time })
        (ok true)))

;; Resume pool
(define-public (resume-pool (pool-id uint))
    (let ((pool (unwrap! (map-get? pools pool-id) ERR_POOL_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set pools pool-id (merge pool { status: POOL_ACTIVE }))
        (print { event: "pool-resumed", pool-id: pool-id, timestamp: stacks-block-time })
        (ok true)))
