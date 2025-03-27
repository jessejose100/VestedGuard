;; VestedGuard: Secure Token & Escrow
;; Features:
;; - Standard token transfer and balance management
;; - Escrow functionality for secure transactions
;; - Vesting schedules for token distribution
;; - Owner-controlled minting and vesting management

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-ESCROW-EXISTS (err u102))
(define-constant ERR-ESCROW-NOT-FOUND (err u103))
(define-constant ERR-ESCROW-COMPLETED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-VESTING-NOT-FOUND (err u106))
(define-constant ERR-VESTING-COMPLETED (err u107))
(define-constant ERR-VESTING-NOT-STARTED (err u108))

(define-constant CONTRACT-OWNER tx-sender)

;; Token parameters
(define-constant TOKEN-NAME "VestedToken")
(define-constant TOKEN-SYMBOL "VST")
(define-constant TOTAL-SUPPLY u1000000000000000)

;; Data maps and variables
(define-map balances { owner: principal } { amount: uint })
(define-map escrows { escrow-id: uint } { sender: principal, receiver: principal, amount: uint, completed: bool })
(define-map vesting-schedules { vesting-id: uint } { recipient: principal, start-block: uint, end-block: uint, total-amount: uint, claimed-amount: uint })

(define-data-var next-escrow-id uint u1)
(define-data-var next-vesting-id uint u1)

;; Utility functions
(define-read-only (is-owner (user principal))
  (is-eq user CONTRACT-OWNER))

(define-read-only (get-token-name)
  TOKEN-NAME)

(define-read-only (get-token-symbol)
  TOKEN-SYMBOL)

(define-read-only (get-total-supply)
  TOTAL-SUPPLY)

(define-read-only (get-balance (owner principal))
  (let (
      (balance-option (map-get? balances { owner: owner }))
    )
    (if (is-some balance-option)
        (get amount (unwrap! balance-option u0))
        u0
    )
  )
)

(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { escrow-id: escrow-id }))

(define-read-only (get-vesting-schedule (vesting-id uint))
  (map-get? vesting-schedules { vesting-id: vesting-id }))

;; Token transfer function
(define-public (transfer (recipient principal) (amount uint))
  (let (
      (sender tx-sender)
      (sender-balance (get-balance sender))
    )
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    (map-set balances { owner: sender } { amount: (- sender-balance amount) })
    (map-set balances { owner: recipient } { amount: (+ (get-balance recipient) amount) })
    (ok true)
  )
)

;; Minting function (only owner)
(define-public (mint (recipient principal) (amount uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (map-set balances { owner: recipient } { amount: (+ (get-balance recipient) amount) })
    (ok true)
  )
)

;; Escrow functions
(define-public (create-escrow (receiver principal) (amount uint))
  (let (
      (sender tx-sender)
      (sender-balance (get-balance sender))
      (escrow-id (var-get next-escrow-id))
    )
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? escrows { escrow-id: escrow-id })) ERR-ESCROW-EXISTS)
    (map-set balances { owner: sender } { amount: (- sender-balance amount) })
    (map-set escrows { escrow-id: escrow-id } { sender: sender, receiver: receiver, amount: amount, completed: false })
    (var-set next-escrow-id (+ escrow-id u1))
    (ok escrow-id)
  )
)

(define-public (complete-escrow (escrow-id uint))
  (let (
      (escrow (map-get? escrows { escrow-id: escrow-id }))
    )
    (asserts! (is-some escrow) ERR-ESCROW-NOT-FOUND)
    (asserts! (not (get completed (unwrap! escrow ERR-ESCROW-NOT-FOUND))) ERR-ESCROW-COMPLETED)
    (asserts! (is-eq (get receiver (unwrap! escrow ERR-ESCROW-NOT-FOUND)) tx-sender) ERR-NOT-AUTHORIZED)
    (map-set balances { owner: (get receiver (unwrap! escrow ERR-ESCROW-NOT-FOUND)) } { amount: (+ (get-balance (get receiver (unwrap! escrow ERR-ESCROW-NOT-FOUND))) (get amount (unwrap! escrow ERR-ESCROW-NOT-FOUND))) })
    (map-set escrows { escrow-id: escrow-id } { sender: (get sender (unwrap! escrow ERR-ESCROW-NOT-FOUND)), receiver: (get receiver (unwrap! escrow ERR-ESCROW-NOT-FOUND)), amount: (get amount (unwrap! escrow ERR-ESCROW-NOT-FOUND)), completed: true })
    (ok true)
  )
)

(define-public (cancel-escrow (escrow-id uint))
    (let (
        (escrow (map-get? escrows {escrow-id: escrow-id}))
    )
        (asserts! (is-some escrow) ERR-ESCROW-NOT-FOUND)
        (asserts! (not (get completed (unwrap! escrow ERR-ESCROW-NOT-FOUND))) ERR-ESCROW-COMPLETED)
        (asserts! (or (is-eq (get sender (unwrap! escrow ERR-ESCROW-NOT-FOUND)) tx-sender) (is-owner tx-sender)) ERR-NOT-AUTHORIZED)
        (map-set balances {owner: (get sender (unwrap! escrow ERR-ESCROW-NOT-FOUND))} {amount: (+ (get-balance (get sender (unwrap! escrow ERR-ESCROW-NOT-FOUND))) (get amount (unwrap! escrow ERR-ESCROW-NOT-FOUND)))})
        (map-set escrows {escrow-id: escrow-id} {sender: (get sender (unwrap! escrow ERR-ESCROW-NOT-FOUND)), receiver: (get receiver (unwrap! escrow ERR-ESCROW-NOT-FOUND)), amount: (get amount (unwrap! escrow ERR-ESCROW-NOT-FOUND)), completed: true})
        (ok true)
    )
)

;; Time-Release Token Distribution Feature
;; Functions for creating and managing vesting schedules, allowing for time-based token distribution.
(define-public (create-vesting (recipient principal) (start-block uint) (end-block uint) (total-amount uint))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (asserts! (> end-block start-block) ERR-INVALID-AMOUNT)
    (asserts! (>= (get-balance CONTRACT-OWNER) total-amount) ERR-INSUFFICIENT-BALANCE)
    (map-set vesting-schedules { vesting-id: (var-get next-vesting-id) } { recipient: recipient, start-block: start-block, end-block: end-block, total-amount: total-amount, claimed-amount: u0 })
    (map-set balances { owner: CONTRACT-OWNER } { amount: (- (get-balance CONTRACT-OWNER) total-amount) })
    (var-set next-vesting-id (+ (var-get next-vesting-id) u1))
    (ok true)
  )
)

(define-public (claim-vested-tokens (vesting-id uint))
  (let (
      (vesting (map-get? vesting-schedules { vesting-id: vesting-id }))
      (current-block block-height)
    )
    (asserts! (is-some vesting) ERR-VESTING-NOT-FOUND)
    (let (
        (vesting-data (unwrap! vesting ERR-VESTING-NOT-FOUND))
        (recipient (get recipient vesting-data))
        (start-block (get start-block vesting-data))
        (end-block (get end-block vesting-data))
        (total-amount (get total-amount vesting-data))
        (claimed-amount (get claimed-amount vesting-data))
      )
      (asserts! (>= current-block start-block) ERR-VESTING-NOT-STARTED)
      (asserts! (<= current-block end-block) ERR-VESTING-COMPLETED)
      (let (
          (calculated-amount (* (/ (- current-block start-block) (- end-block start-block)) total-amount))
          (eligible-amount (if (<= calculated-amount total-amount) calculated-amount total-amount))
          (amount-to-claim (- eligible-amount claimed-amount))
        )
        (asserts! (> amount-to-claim u0) ERR-INVALID-AMOUNT)
        (map-set balances { owner: recipient } { amount: (+ (get-balance recipient) amount-to-claim) })
        (map-set vesting-schedules { vesting-id: vesting-id } { recipient: recipient, start-block: start-block, end-block: end-block, total-amount: total-amount, claimed-amount: eligible-amount })
        (ok true)
      )
    )
  )
)

