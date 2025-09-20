;; On-Chain Payment Enforcement Contract
;; Manages automatic payments, deposits, and financial transactions for leases

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-amount (err u203))
(define-constant err-insufficient-balance (err u204))
(define-constant err-payment-not-due (err u205))
(define-constant err-late-payment (err u206))
(define-constant err-invalid-state (err u207))
(define-constant err-deposit-locked (err u208))
(define-constant err-refund-pending (err u209))
(define-constant err-payment-already-made (err u210))

;; Payment cycle constants (in blocks)
(define-constant blocks-per-month u4320) ;; Approximately 30 days
(define-constant late-fee-percentage u5) ;; 5% late fee
(define-constant grace-period-blocks u144) ;; 1 day grace period

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var payment-id-nonce uint u0)
(define-data-var total-collected uint u0)
(define-data-var total-refunded uint u0)

;; Data Maps
(define-map rental-balances
  { tenant: principal, lease-id: uint }
  {
    balance: uint,
    last-payment-block: uint,
    payments-made: uint,
    late-fees: uint,
    status: (string-ascii 20)
  }
)

(define-map payment-schedule
  { lease-id: uint, payment-period: uint }
  {
    amount: uint,
    due-block: uint,
    paid-block: (optional uint),
    late-fee: uint,
    status: (string-ascii 20)
  }
)

(define-map payment-transactions
  { payment-id: uint }
  {
    lease-id: uint,
    tenant: principal,
    landlord: principal,
    amount: uint,
    payment-type: (string-ascii 30),
    processed-at: uint,
    transaction-hash: (buff 32)
  }
)

(define-map deposit-escrow
  { tenant: principal, lease-id: uint }
  {
    amount: uint,
    locked: bool,
    refund-requested: bool,
    refund-approved: bool,
    refund-amount: uint
  }
)

(define-map landlord-earnings
  { landlord: principal }
  {
    total-earned: uint,
    available-balance: uint,
    withdrawn: uint,
    active-leases: uint
  }
)

;; Public Functions

;; Initialize rental balance for new lease
(define-public (initialize-rental-balance (tenant principal) (lease-id uint) (deposit-amount uint))
  (let ((payment-id (+ (var-get payment-id-nonce) u1)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (> deposit-amount u0) err-invalid-amount)
    (asserts! (is-none (map-get? rental-balances { tenant: tenant, lease-id: lease-id })) err-invalid-state)
    
    ;; Initialize rental balance
    (map-set rental-balances
      { tenant: tenant, lease-id: lease-id }
      {
        balance: deposit-amount,
        last-payment-block: stacks-block-height,
        payments-made: u0,
        late-fees: u0,
        status: "active"
      }
    )
    
    ;; Initialize deposit escrow
    (map-set deposit-escrow
      { tenant: tenant, lease-id: lease-id }
      {
        amount: deposit-amount,
        locked: true,
        refund-requested: false,
        refund-approved: false,
        refund-amount: u0
      }
    )
    
    (var-set payment-id-nonce payment-id)
    (ok payment-id)
  )
)

;; Add funds to rental balance
(define-public (add-rental-funds (lease-id uint) (amount uint))
  (let (
    (current-balance (unwrap! (map-get? rental-balances { tenant: tx-sender, lease-id: lease-id }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-eq (get status current-balance) "active") err-invalid-state)
    
    ;; Transfer funds to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update rental balance
    (map-set rental-balances
      { tenant: tx-sender, lease-id: lease-id }
      (merge current-balance { balance: (+ (get balance current-balance) amount) })
    )
    
    (ok true)
  )
)

;; Process monthly rent payment automatically
(define-public (process-rent-payment (tenant principal) (lease-id uint) (landlord principal) (rent-amount uint))
  (let (
    (rental-balance (unwrap! (map-get? rental-balances { tenant: tenant, lease-id: lease-id }) err-not-found))
    (payment-id (+ (var-get payment-id-nonce) u1))
    (current-period (get-payment-period (get last-payment-block rental-balance)))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (>= (get balance rental-balance) rent-amount) err-insufficient-balance)
    (asserts! (is-eq (get status rental-balance) "active") err-invalid-state)
    (asserts! (>= stacks-block-height (+ (get last-payment-block rental-balance) blocks-per-month)) err-payment-not-due)
    
    ;; Calculate late fees if applicable
    (let (
      (due-block (+ (get last-payment-block rental-balance) blocks-per-month))
      (late-fee (if (> stacks-block-height (+ due-block grace-period-blocks))
                   (/ (* rent-amount late-fee-percentage) u100)
                   u0))
      (total-payment (+ rent-amount late-fee))
    )
      (asserts! (>= (get balance rental-balance) total-payment) err-insufficient-balance)
      
      ;; Update rental balance
      (map-set rental-balances
        { tenant: tenant, lease-id: lease-id }
        (merge rental-balance {
          balance: (- (get balance rental-balance) total-payment),
          last-payment-block: stacks-block-height,
          payments-made: (+ (get payments-made rental-balance) u1),
          late-fees: (+ (get late-fees rental-balance) late-fee)
        })
      )
      
      ;; Record payment transaction
      (map-set payment-transactions
        { payment-id: payment-id }
        {
          lease-id: lease-id,
          tenant: tenant,
          landlord: landlord,
          amount: total-payment,
          payment-type: "monthly-rent",
          processed-at: stacks-block-height,
          transaction-hash: (sha256 (unwrap-panic (to-consensus-buff? { payment-id: payment-id, block: stacks-block-height })))
        }
      )
      
      ;; Record payment schedule entry
      (map-set payment-schedule
        { lease-id: lease-id, payment-period: current-period }
        {
          amount: rent-amount,
          due-block: due-block,
          paid-block: (some stacks-block-height),
          late-fee: late-fee,
          status: (if (> late-fee u0) "paid-late" "paid-on-time")
        }
      )
      
      ;; Update landlord earnings
      (let (
        (current-earnings (default-to 
          { total-earned: u0, available-balance: u0, withdrawn: u0, active-leases: u0 }
          (map-get? landlord-earnings { landlord: landlord })
        ))
      )
        (map-set landlord-earnings
          { landlord: landlord }
          (merge current-earnings {
            total-earned: (+ (get total-earned current-earnings) total-payment),
            available-balance: (+ (get available-balance current-earnings) total-payment)
          })
        )
      )
      
      ;; Transfer payment to landlord
      (try! (as-contract (stx-transfer? total-payment tx-sender landlord)))
      
      (var-set payment-id-nonce payment-id)
      (var-set total-collected (+ (var-get total-collected) total-payment))
      (ok payment-id)
    )
  )
)

;; Request deposit refund (tenant)
(define-public (request-deposit-refund (lease-id uint))
  (let (
    (deposit-info (unwrap! (map-get? deposit-escrow { tenant: tx-sender, lease-id: lease-id }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (not (get locked deposit-info)) err-deposit-locked)
    (asserts! (not (get refund-requested deposit-info)) err-refund-pending)
    
    ;; Mark refund as requested
    (map-set deposit-escrow
      { tenant: tx-sender, lease-id: lease-id }
      (merge deposit-info { refund-requested: true })
    )
    
    (ok true)
  )
)

;; Approve deposit refund (landlord)
(define-public (approve-deposit-refund (tenant principal) (lease-id uint) (refund-amount uint))
  (let (
    (deposit-info (unwrap! (map-get? deposit-escrow { tenant: tenant, lease-id: lease-id }) err-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (get refund-requested deposit-info) err-invalid-state)
    (asserts! (<= refund-amount (get amount deposit-info)) err-invalid-amount)
    
    ;; Mark refund as approved
    (map-set deposit-escrow
      { tenant: tenant, lease-id: lease-id }
      (merge deposit-info {
        refund-approved: true,
        refund-amount: refund-amount
      })
    )
    
    (ok true)
  )
)

;; Process deposit refund
(define-public (process-deposit-refund (tenant principal) (lease-id uint))
  (let (
    (deposit-info (unwrap! (map-get? deposit-escrow { tenant: tenant, lease-id: lease-id }) err-not-found))
    (payment-id (+ (var-get payment-id-nonce) u1))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (get refund-approved deposit-info) err-unauthorized)
    (asserts! (> (get refund-amount deposit-info) u0) err-invalid-amount)
    
    ;; Transfer refund to tenant
    (try! (as-contract (stx-transfer? (get refund-amount deposit-info) tx-sender tenant)))
    
    ;; Record refund transaction
    (map-set payment-transactions
      { payment-id: payment-id }
      {
        lease-id: lease-id,
        tenant: tenant,
        landlord: tx-sender,
        amount: (get refund-amount deposit-info),
        payment-type: "deposit-refund",
        processed-at: stacks-block-height,
        transaction-hash: (sha256 (unwrap-panic (to-consensus-buff? { payment-id: payment-id, block: stacks-block-height })))
      }
    )
    
    ;; Clear deposit escrow
    (map-delete deposit-escrow { tenant: tenant, lease-id: lease-id })
    
    (var-set payment-id-nonce payment-id)
    (var-set total-refunded (+ (var-get total-refunded) (get refund-amount deposit-info)))
    (ok payment-id)
  )
)

;; Emergency pause (contract owner only)
(define-public (pause-payments)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Resume operations (contract owner only)
(define-public (resume-payments)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-rental-balance (tenant principal) (lease-id uint))
  (map-get? rental-balances { tenant: tenant, lease-id: lease-id })
)

(define-read-only (get-payment-schedule (lease-id uint) (payment-period uint))
  (map-get? payment-schedule { lease-id: lease-id, payment-period: payment-period })
)

(define-read-only (get-payment-transaction (payment-id uint))
  (map-get? payment-transactions { payment-id: payment-id })
)

(define-read-only (get-deposit-escrow (tenant principal) (lease-id uint))
  (map-get? deposit-escrow { tenant: tenant, lease-id: lease-id })
)

(define-read-only (get-landlord-earnings (landlord principal))
  (map-get? landlord-earnings { landlord: landlord })
)

(define-read-only (get-payment-period (last-payment-block uint))
  (/ (- stacks-block-height last-payment-block) blocks-per-month)
)

(define-read-only (is-payment-due (tenant principal) (lease-id uint))
  (match (map-get? rental-balances { tenant: tenant, lease-id: lease-id })
    rental-balance (>= stacks-block-height (+ (get last-payment-block rental-balance) blocks-per-month))
    false
  )
)

(define-read-only (calculate-late-fee (rent-amount uint))
  (/ (* rent-amount late-fee-percentage) u100)
)

(define-read-only (get-contract-stats)
  {
    total-collected: (var-get total-collected),
    total-refunded: (var-get total-refunded),
    payment-count: (var-get payment-id-nonce),
    contract-paused: (var-get contract-paused)
  }
)

(define-read-only (get-contract-owner)
  contract-owner
)

