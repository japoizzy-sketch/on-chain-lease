;; On-Chain Lease Management Contract
;; Handles property registration, lease creation, and agreement management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-lease-exists (err u104))
(define-constant err-invalid-duration (err u105))
(define-constant err-property-not-available (err u106))
(define-constant err-invalid-state (err u107))
(define-constant err-insufficient-deposit (err u108))
(define-constant err-lease-expired (err u109))
(define-constant err-early-termination (err u110))

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var property-id-nonce uint u0)
(define-data-var lease-id-nonce uint u0)

;; Data Maps
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    address: (string-ascii 200),
    rent-amount: uint,
    security-deposit: uint,
    available: bool,
    property-type: (string-ascii 50),
    created-at: uint
  }
)

(define-map leases
  { lease-id: uint }
  {
    property-id: uint,
    landlord: principal,
    tenant: principal,
    rent-amount: uint,
    security-deposit: uint,
    lease-start: uint,
    lease-end: uint,
    status: (string-ascii 20),
    deposit-paid: uint,
    last-payment: uint,
    created-at: uint
  }
)

(define-map property-leases
  { property-id: uint }
  { active-lease-id: (optional uint) }
)

(define-map lease-payments
  { lease-id: uint, payment-month: uint }
  {
    amount: uint,
    paid-at: uint,
    payment-type: (string-ascii 20)
  }
)

(define-map tenant-deposits
  { tenant: principal, lease-id: uint }
  { amount: uint, locked: bool }
)

;; Public Functions

;; Register a new property for lease
(define-public (register-property (address (string-ascii 200)) (rent-amount uint) (security-deposit uint) (property-type (string-ascii 50)))
  (let ((property-id (+ (var-get property-id-nonce) u1)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (> rent-amount u0) err-invalid-amount)
    (asserts! (> security-deposit u0) err-invalid-amount)
    
    (map-set properties
      { property-id: property-id }
      {
        owner: tx-sender,
        address: address,
        rent-amount: rent-amount,
        security-deposit: security-deposit,
        available: true,
        property-type: property-type,
        created-at: stacks-block-height
      }
    )
    
    (var-set property-id-nonce property-id)
    (ok property-id)
  )
)

;; Create a lease application
(define-public (apply-for-lease (property-id uint) (lease-duration uint))
  (let (
    (property-info (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
    (lease-id (+ (var-get lease-id-nonce) u1))
    (lease-start stacks-block-height)
    (lease-end (+ stacks-block-height lease-duration))
  )
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (get available property-info) err-property-not-available)
    (asserts! (> lease-duration u0) err-invalid-duration)
    (asserts! (not (is-eq tx-sender (get owner property-info))) err-unauthorized)
    (asserts! (is-none (get active-lease-id (default-to { active-lease-id: none } (map-get? property-leases { property-id: property-id })))) err-lease-exists)
    
    ;; Create lease record
    (map-set leases
      { lease-id: lease-id }
      {
        property-id: property-id,
        landlord: (get owner property-info),
        tenant: tx-sender,
        rent-amount: (get rent-amount property-info),
        security-deposit: (get security-deposit property-info),
        lease-start: lease-start,
        lease-end: lease-end,
        status: "pending",
        deposit-paid: u0,
        last-payment: u0,
        created-at: stacks-block-height
      }
    )
    
    (var-set lease-id-nonce lease-id)
    (ok lease-id)
  )
)

;; Approve lease application (landlord only)
(define-public (approve-lease (lease-id uint))
  (let ((lease-info (unwrap! (map-get? leases { lease-id: lease-id }) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (is-eq tx-sender (get landlord lease-info)) err-unauthorized)
    (asserts! (is-eq (get status lease-info) "pending") err-invalid-state)
    
    ;; Update lease status
    (map-set leases
      { lease-id: lease-id }
      (merge lease-info { status: "approved" })
    )
    
    ;; Mark property as unavailable and set active lease
    (map-set properties
      { property-id: (get property-id lease-info) }
      (merge (unwrap-panic (map-get? properties { property-id: (get property-id lease-info) }))
             { available: false })
    )
    
    (map-set property-leases
      { property-id: (get property-id lease-info) }
      { active-lease-id: (some lease-id) }
    )
    
    (ok true)
  )
)

;; Pay security deposit and activate lease
(define-public (pay-security-deposit (lease-id uint))
  (let ((lease-info (unwrap! (map-get? leases { lease-id: lease-id }) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (is-eq tx-sender (get tenant lease-info)) err-unauthorized)
    (asserts! (is-eq (get status lease-info) "approved") err-invalid-state)
    (asserts! (is-eq (get deposit-paid lease-info) u0) err-invalid-state)
    
    ;; Transfer security deposit to contract
    (try! (stx-transfer? (get security-deposit lease-info) tx-sender (as-contract tx-sender)))
    
    ;; Update lease with deposit payment
    (map-set leases
      { lease-id: lease-id }
      (merge lease-info {
        status: "active",
        deposit-paid: (get security-deposit lease-info),
        last-payment: stacks-block-height
      })
    )
    
    ;; Record deposit in tenant deposits map
    (map-set tenant-deposits
      { tenant: tx-sender, lease-id: lease-id }
      { amount: (get security-deposit lease-info), locked: true }
    )
    
    (ok true)
  )
)

;; Terminate lease (early termination)
(define-public (terminate-lease (lease-id uint))
  (let ((lease-info (unwrap! (map-get? leases { lease-id: lease-id }) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (or (is-eq tx-sender (get landlord lease-info)) (is-eq tx-sender (get tenant lease-info))) err-unauthorized)
    (asserts! (is-eq (get status lease-info) "active") err-invalid-state)
    (asserts! (< stacks-block-height (get lease-end lease-info)) err-lease-expired)
    
    ;; Update lease status
    (map-set leases
      { lease-id: lease-id }
      (merge lease-info { status: "terminated" })
    )
    
    ;; Make property available again
    (map-set properties
      { property-id: (get property-id lease-info) }
      (merge (unwrap-panic (map-get? properties { property-id: (get property-id lease-info) }))
             { available: true })
    )
    
    ;; Clear active lease from property
    (map-set property-leases
      { property-id: (get property-id lease-info) }
      { active-lease-id: none }
    )
    
    ;; Unlock tenant deposit for refund processing
    (map-set tenant-deposits
      { tenant: (get tenant lease-info), lease-id: lease-id }
      { amount: (get security-deposit lease-info), locked: false }
    )
    
    (ok true)
  )
)

;; Complete lease (natural expiration)
(define-public (complete-lease (lease-id uint))
  (let ((lease-info (unwrap! (map-get? leases { lease-id: lease-id }) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-invalid-state)
    (asserts! (is-eq (get status lease-info) "active") err-invalid-state)
    (asserts! (>= stacks-block-height (get lease-end lease-info)) err-early-termination)
    
    ;; Update lease status to completed
    (map-set leases
      { lease-id: lease-id }
      (merge lease-info { status: "completed" })
    )
    
    ;; Make property available again
    (map-set properties
      { property-id: (get property-id lease-info) }
      (merge (unwrap-panic (map-get? properties { property-id: (get property-id lease-info) }))
             { available: true })
    )
    
    ;; Clear active lease from property
    (map-set property-leases
      { property-id: (get property-id lease-info) }
      { active-lease-id: none }
    )
    
    ;; Unlock tenant deposit for refund processing
    (map-set tenant-deposits
      { tenant: (get tenant lease-info), lease-id: lease-id }
      { amount: (get security-deposit lease-info), locked: false }
    )
    
    (ok true)
  )
)

;; Emergency pause (contract owner only)
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Resume operations (contract owner only)
(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-property (property-id uint))
  (map-get? properties { property-id: property-id })
)

(define-read-only (get-lease (lease-id uint))
  (map-get? leases { lease-id: lease-id })
)

(define-read-only (get-property-lease (property-id uint))
  (map-get? property-leases { property-id: property-id })
)

(define-read-only (get-tenant-deposit (tenant principal) (lease-id uint))
  (map-get? tenant-deposits { tenant: tenant, lease-id: lease-id })
)

(define-read-only (get-lease-payment (lease-id uint) (payment-month uint))
  (map-get? lease-payments { lease-id: lease-id, payment-month: payment-month })
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-contract-owner)
  contract-owner
)

(define-read-only (get-property-count)
  (var-get property-id-nonce)
)

(define-read-only (get-lease-count)
  (var-get lease-id-nonce)
)
