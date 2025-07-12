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