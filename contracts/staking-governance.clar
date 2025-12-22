;; staking-governance.clar
;; Governance system for staking pool parameters
;; Uses Clarity 4 epoch 3.3 with Chainhook integration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u15001))
(define-constant ERR_INVALID_PROPOSAL (err u15002))
(define-constant ERR_VOTING_ENDED (err u15003))
(define-constant ERR_INSUFFICIENT_STAKE (err u15004))

(define-data-var proposal-counter uint u0)
(define-data-var min-stake-to-propose uint u1000000)
(define-data-var voting-period uint u1440)

(define-map governance-proposals
    uint
    {
        proposer: principal,
        proposal-type: (string-ascii 32),
        new-value: uint,
        description: (string-utf8 512),
        created-at: uint,
        voting-ends-at: uint,
        votes-for: uint,
        votes-against: uint,
        total-voting-power: uint,
        executed: bool,
        passed: bool
    }
)

(define-map proposal-votes
    { proposal-id: uint, voter: principal }
    {
        vote: bool,
        voting-power: uint,
        voted-at: uint
    }
)

(define-map staker-voting-power
    principal
    {
        staked-amount: uint,
        voting-power: uint,
        last-updated: uint
    }
)

(define-public (update-voting-power (staker principal) (staked-amount uint))
    (let
        (
            (voting-power staked-amount)
        )
        (map-set staker-voting-power staker {
            staked-amount: staked-amount,
            voting-power: voting-power,
            last-updated: stacks-block-time
        })
        (print {
            event: "voting-power-updated",
            staker: staker,
            staked-amount: staked-amount,
            voting-power: voting-power,
            timestamp: stacks-block-time
        })
        (ok voting-power)
    )
)

(define-public (create-proposal
    (proposal-type (string-ascii 32))
    (new-value uint)
    (description (string-utf8 512)))
    (let
        (
            (staker-power (unwrap! (map-get? staker-voting-power tx-sender) ERR_INSUFFICIENT_STAKE))
            (proposal-id (+ (var-get proposal-counter) u1))
            (voting-ends (+ stacks-block-time (var-get voting-period)))
        )
        (asserts! (>= (get staked-amount staker-power) (var-get min-stake-to-propose)) ERR_INSUFFICIENT_STAKE)
        
        (map-set governance-proposals proposal-id {
            proposer: tx-sender,
            proposal-type: proposal-type,
            new-value: new-value,
            description: description,
            created-at: stacks-block-time,
            voting-ends-at: voting-ends,
            votes-for: u0,
            votes-against: u0,
            total-voting-power: u0,
            executed: false,
            passed: false
        })
        (var-set proposal-counter proposal-id)
        
        (print {
            event: "governance-proposal-created",
            proposal-id: proposal-id,
            proposer: tx-sender,
            proposal-type: proposal-type,
            new-value: new-value,
            voting-ends-at: voting-ends,
            timestamp: stacks-block-time
        })
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let
        (
            (proposal (unwrap! (map-get? governance-proposals proposal-id) ERR_INVALID_PROPOSAL))
            (voter-power (unwrap! (map-get? staker-voting-power tx-sender) ERR_INSUFFICIENT_STAKE))
            (voting-power (get voting-power voter-power))
        )
        (asserts! (< stacks-block-time (get voting-ends-at proposal)) ERR_VOTING_ENDED)
        (asserts! (> voting-power u0) ERR_INSUFFICIENT_STAKE)
        
        (map-set proposal-votes
            { proposal-id: proposal-id, voter: tx-sender }
            {
                vote: vote-for,
                voting-power: voting-power,
                voted-at: stacks-block-time
            })
        
        (map-set governance-proposals proposal-id
            (merge proposal {
                votes-for: (if vote-for (+ (get votes-for proposal) voting-power) (get votes-for proposal)),
                votes-against: (if (not vote-for) (+ (get votes-against proposal) voting-power) (get votes-against proposal)),
                total-voting-power: (+ (get total-voting-power proposal) voting-power)
            }))
        
        (print {
            event: "governance-vote-cast",
            proposal-id: proposal-id,
            voter: tx-sender,
            vote-for: vote-for,
            voting-power: voting-power,
            timestamp: stacks-block-time
        })
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (map-get? governance-proposals proposal-id) ERR_INVALID_PROPOSAL))
            (passed (> (get votes-for proposal) (get votes-against proposal)))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (>= stacks-block-time (get voting-ends-at proposal)) ERR_VOTING_ENDED)
        (asserts! (not (get executed proposal)) ERR_INVALID_PROPOSAL)
        
        (map-set governance-proposals proposal-id
            (merge proposal {
                executed: true,
                passed: passed
            }))
        
        (print {
            event: "governance-proposal-executed",
            proposal-id: proposal-id,
            passed: passed,
            votes-for: (get votes-for proposal),
            votes-against: (get votes-against proposal),
            timestamp: stacks-block-time
        })
        (ok passed)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? governance-proposals proposal-id)
)

(define-read-only (get-voting-power (staker principal))
    (map-get? staker-voting-power staker)
)
