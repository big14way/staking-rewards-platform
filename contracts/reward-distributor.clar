;; reward-distributor.clar
;; Automated reward distribution and bonus calculations

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u23101))

;; Bonus tiers based on stake duration
(define-constant TIER_BRONZE u0)   ;; < 30 days: 0% bonus
(define-constant TIER_SILVER u1)   ;; 30-90 days: 10% bonus
(define-constant TIER_GOLD u2)     ;; 90-180 days: 25% bonus
(define-constant TIER_PLATINUM u3) ;; > 180 days: 50% bonus

;; Duration thresholds in seconds
(define-constant THIRTY_DAYS u2592000)
(define-constant NINETY_DAYS u7776000)
(define-constant ONE_EIGHTY_DAYS u15552000)

;; Bonus rates (basis points)
(define-constant SILVER_BONUS u1000)    ;; 10%
(define-constant GOLD_BONUS u2500)      ;; 25%
(define-constant PLATINUM_BONUS u5000)  ;; 50%

;; ========================================
;; Data Maps
;; ========================================

(define-map user-tiers
    principal
    {
        current-tier: uint,
        tier-achieved-at: uint,
        total-bonus-earned: uint
    }
)

(define-map referral-bonuses
    { referrer: principal, referee: principal }
    {
        bonus-paid: uint,
        created-at: uint
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-tier-for-duration (duration uint))
    (if (>= duration ONE_EIGHTY_DAYS)
        TIER_PLATINUM
        (if (>= duration NINETY_DAYS)
            TIER_GOLD
            (if (>= duration THIRTY_DAYS)
                TIER_SILVER
                TIER_BRONZE))))

(define-read-only (get-bonus-rate (tier uint))
    (if (is-eq tier TIER_PLATINUM)
        PLATINUM_BONUS
        (if (is-eq tier TIER_GOLD)
            GOLD_BONUS
            (if (is-eq tier TIER_SILVER)
                SILVER_BONUS
                u0))))

(define-read-only (calculate-bonus (base-reward uint) (tier uint))
    (let ((bonus-rate (get-bonus-rate tier)))
        (/ (* base-reward bonus-rate) u10000)))

(define-read-only (get-user-tier (user principal))
    (default-to 
        { current-tier: TIER_BRONZE, tier-achieved-at: u0, total-bonus-earned: u0 }
        (map-get? user-tiers user)))

(define-read-only (get-tier-name (tier uint))
    (if (is-eq tier TIER_PLATINUM) "Platinum"
        (if (is-eq tier TIER_GOLD) "Gold"
            (if (is-eq tier TIER_SILVER) "Silver"
                "Bronze"))))

;; ========================================
;; Public Functions
;; ========================================

;; Update user tier based on staking duration
(define-public (update-user-tier (user principal) (stake-duration uint))
    (let
        (
            (new-tier (get-tier-for-duration stake-duration))
            (current-user-tier (get-user-tier user))
            (current-time stacks-block-time)
        )
        ;; Update if tier improved
        (if (> new-tier (get current-tier current-user-tier))
            (begin
                (map-set user-tiers user (merge current-user-tier {
                    current-tier: new-tier,
                    tier-achieved-at: current-time
                }))
                
                ;; EMIT EVENT: tier-upgraded
                (print {
                    event: "tier-upgraded",
                    user: user,
                    old-tier: (get current-tier current-user-tier),
                    new-tier: new-tier,
                    tier-name: (get-tier-name new-tier),
                    timestamp: current-time
                })
                
                (ok new-tier))
            (ok (get current-tier current-user-tier)))))

;; Record bonus earned
(define-public (record-bonus (user principal) (bonus-amount uint))
    (let
        (
            (current-user-tier (get-user-tier user))
        )
        (map-set user-tiers user (merge current-user-tier {
            total-bonus-earned: (+ (get total-bonus-earned current-user-tier) bonus-amount)
        }))
        
        ;; EMIT EVENT: bonus-earned
        (print {
            event: "bonus-earned",
            user: user,
            tier: (get current-tier current-user-tier),
            amount: bonus-amount,
            timestamp: stacks-block-time
        })
        
        (ok bonus-amount)))

;; Process referral bonus
(define-public (process-referral (referrer principal) (referee principal) (stake-amount uint))
    (let
        (
            (referral-bonus (/ (* stake-amount u100) u10000)) ;; 1% referral bonus
            (current-time stacks-block-time)
        )
        ;; Record referral
        (map-set referral-bonuses { referrer: referrer, referee: referee } {
            bonus-paid: referral-bonus,
            created-at: current-time
        })
        
        ;; EMIT EVENT: referral-bonus
        (print {
            event: "referral-bonus",
            referrer: referrer,
            referee: referee,
            bonus: referral-bonus,
            stake-amount: stake-amount,
            timestamp: current-time
        })
        
        (ok referral-bonus)))
