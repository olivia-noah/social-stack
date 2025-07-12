;; SocialStack - Bitcoin-Backed Social Network Protocol
;;
;; Summary:
;; A revolutionary decentralized social networking protocol that transforms 
;; digital interactions through economic incentives. Built on Stacks blockchain 
;; with Bitcoin's security, enabling stake-weighted social interactions, 
;; content monetization, and trustless reputation systems.
;;
;; Description:
;; SocialStack pioneers the next generation of social media by introducing 
;; economic skin-in-the-game for every social interaction. Users stake STX 
;; tokens to create profiles, amplify content, and build reputation. The 
;; protocol eliminates fake accounts and spam through economic barriers while 
;; rewarding genuine engagement. Every follow, post, and endorsement is 
;; recorded immutably on Bitcoin's settlement layer, creating a transparent 
;; and manipulation-resistant social graph that scales with user investment.
;;
;; Core Innovation:
;; - Stake-to-participate model eliminates bot networks and spam
;; - Economic reputation scoring based on community investment
;; - Content monetization through boosting and endorsement mechanisms
;; - Trustless social verification without centralized authorities
;; - Cross-platform identity portability secured by Bitcoin finality

;; PROTOCOL CONSTANTS

(define-constant CONTRACT_OWNER tx-sender)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PROFILE_EXISTS (err u101))
(define-constant ERR_PROFILE_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_ALREADY_FOLLOWING (err u105))
(define-constant ERR_NOT_FOLLOWING (err u106))
(define-constant ERR_SELF_FOLLOW (err u107))
(define-constant ERR_ALREADY_ENDORSED (err u108))
(define-constant ERR_POST_NOT_FOUND (err u109))
(define-constant ERR_INVALID_POST_ID (err u110))

;; Minimum stake requirements (in microSTX)
(define-constant MIN_PROFILE_STAKE u1000000) ;; 1 STX - Profile creation barrier
(define-constant MIN_POST_BOOST u100000) ;; 0.1 STX - Content amplification
(define-constant MIN_ENDORSEMENT_STAKE u500000) ;; 0.5 STX - Reputation backing

;; PROTOCOL STATE VARIABLES

(define-data-var next-profile-id uint u1)
(define-data-var next-post-id uint u1)
(define-data-var protocol-fee-rate uint u100) ;; 1% = 100 basis points

;; CORE DATA STRUCTURES

;; User Profile Registry
(define-map profiles
  { profile-id: uint }
  {
    owner: principal,
    username: (string-ascii 50),
    bio: (string-utf8 280),
    avatar-url: (string-ascii 200),
    created-at: uint,
    staked-amount: uint,
    reputation-score: uint,
    follower-count: uint,
    following-count: uint,
    post-count: uint,
    total-endorsements: uint,
    is-active: bool,
  }
)

;; Username Resolution System
(define-map username-to-profile
  (string-ascii 50)
  uint
)

;; Principal Identity Mapping
(define-map principal-to-profile
  principal
  uint
)

;; Social Graph Relationships
(define-map following
  {
    follower: uint,
    following: uint,
  }
  {
    followed-at: uint,
    is-active: bool,
  }
)

;; Content Publishing System
(define-map posts
  { post-id: uint }
  {
    author: uint,
    content: (string-utf8 500),
    created-at: uint,
    boosted-amount: uint,
    endorsement-count: uint,
    is-active: bool,
  }
)

;; Content Endorsement Registry
(define-map post-endorsements
  {
    post-id: uint,
    endorser: uint,
  }
  {
    endorsed-at: uint,
    stake-amount: uint,
  }
)

;; Profile Reputation System
(define-map profile-endorsements
  {
    endorser: uint,
    endorsed: uint,
  }
  {
    endorsed-at: uint,
    stake-amount: uint,
    message: (string-utf8 140),
  }
)

;; Staking Pool Management
(define-map profile-stakes
  {
    profile-id: uint,
    staker: principal,
  }
  {
    amount: uint,
    staked-at: uint,
  }
)

;; Content Monetization Tracking
(define-map post-boosts
  {
    post-id: uint,
    booster: principal,
  }
  {
    amount: uint,
    boosted-at: uint,
  }
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieve profile by unique ID
(define-read-only (get-profile (profile-id uint))
  (map-get? profiles { profile-id: profile-id })
)

;; Lookup profile by username
(define-read-only (get-profile-by-username (username (string-ascii 50)))
  (match (map-get? username-to-profile username)
    profile-id (get-profile profile-id)
    none
  )
)

;; Find profile by wallet address
(define-read-only (get-profile-by-principal (user principal))
  (match (map-get? principal-to-profile user)
    profile-id (get-profile profile-id)
    none
  )
)

;; Check username availability
(define-read-only (is-username-available (username (string-ascii 50)))
  (is-none (map-get? username-to-profile username))
)

;; Verify following relationship
(define-read-only (is-following
    (follower-id uint)
    (following-id uint)
  )
  (match (map-get? following {
    follower: follower-id,
    following: following-id,
  })
    follow-data (get is-active follow-data)
    false
  )
)

;; Retrieve content by post ID
(define-read-only (get-post (post-id uint))
  (map-get? posts { post-id: post-id })
)

;; Get next available profile ID
(define-read-only (get-next-profile-id)
  (var-get next-profile-id)
)

;; Get next available post ID
(define-read-only (get-next-post-id)
  (var-get next-post-id)
)

;; Calculate dynamic reputation score
(define-read-only (calculate-reputation-score (profile-id uint))
  (match (get-profile profile-id)
    profile-data (let (
        (base-score (get staked-amount profile-data))
        (follower-bonus (* (get follower-count profile-data) u1000))
        (endorsement-bonus (* (get total-endorsements profile-data) u2000))
        (post-bonus (* (get post-count profile-data) u500))
      )
      (+ base-score (+ follower-bonus (+ endorsement-bonus post-bonus)))
    )
    u0
  )
)

;; PROFILE MANAGEMENT FUNCTIONS

;; Create new user profile with initial stake
(define-public (create-profile
    (username (string-ascii 50))
    (bio (string-utf8 280))
    (avatar-url (string-ascii 200))
  )
  (let (
      (profile-id (var-get next-profile-id))
      (current-block stacks-block-height)
    )
    ;; Validate profile creation requirements
    (asserts! (is-none (map-get? principal-to-profile tx-sender))
      ERR_PROFILE_EXISTS
    )
    (asserts! (is-username-available username) ERR_PROFILE_EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) MIN_PROFILE_STAKE)
      ERR_INSUFFICIENT_FUNDS
    )
    ;; Lock initial stake
    (try! (stx-transfer? MIN_PROFILE_STAKE tx-sender (as-contract tx-sender)))
    ;; Initialize profile data
    (map-set profiles { profile-id: profile-id } {
      owner: tx-sender,
      username: username,
      bio: bio,
      avatar-url: avatar-url,
      created-at: current-block,
      staked-amount: MIN_PROFILE_STAKE,
      reputation-score: MIN_PROFILE_STAKE,
      follower-count: u0,
      following-count: u0,
      post-count: u0,
      total-endorsements: u0,
      is-active: true,
    })
    ;; Register identity mappings
    (map-set username-to-profile username profile-id)
    (map-set principal-to-profile tx-sender profile-id)
    (map-set profile-stakes {
      profile-id: profile-id,
      staker: tx-sender,
    } {
      amount: MIN_PROFILE_STAKE,
      staked-at: current-block,
    })
    ;; Increment profile counter
    (var-set next-profile-id (+ profile-id u1))
    (ok profile-id)
  )
)

;; Update profile metadata
(define-public (update-profile
    (bio (string-utf8 280))
    (avatar-url (string-ascii 200))
  )
  (let ((profile-result (map-get? principal-to-profile tx-sender)))
    (match profile-result
      profile-id (match (get-profile profile-id)
        profile-data (begin
          (map-set profiles { profile-id: profile-id }
            (merge profile-data {
              bio: bio,
              avatar-url: avatar-url,
            })
          )
          (ok true)
        )
        ERR_PROFILE_NOT_FOUND
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)

;; Increase reputation stake
(define-public (stake-for-reputation (amount uint))
  (let (
      (profile-result (map-get? principal-to-profile tx-sender))
      (current-block stacks-block-height)
    )
    ;; Validate staking parameters
    (asserts! (>= amount MIN_POST_BOOST) ERR_INVALID_AMOUNT)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    (match profile-result
      profile-id (begin
        ;; Lock additional stake
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        ;; Update profile stake amount
        (match (get-profile profile-id)
          profile-data (map-set profiles { profile-id: profile-id }
            (merge profile-data { staked-amount: (+ (get staked-amount profile-data) amount) })
          )
          false
        )
        ;; Record stake transaction
        (map-set profile-stakes {
          profile-id: profile-id,
          staker: tx-sender,
        } {
          amount: amount,
          staked-at: current-block,
        })
        (ok true)
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)