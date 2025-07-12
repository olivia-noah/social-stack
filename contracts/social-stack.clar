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

;; SOCIAL GRAPH FUNCTIONS

;; Follow another user
(define-public (follow-user (following-id uint))
  (let (
      (follower-profile-result (map-get? principal-to-profile tx-sender))
      (current-block stacks-block-height)
    )
    (match follower-profile-result
      follower-id (begin
        ;; Validate follow operation
        (asserts! (not (is-eq follower-id following-id)) ERR_SELF_FOLLOW)
        (asserts! (is-some (get-profile following-id)) ERR_PROFILE_NOT_FOUND)
        (asserts! (not (is-following follower-id following-id))
          ERR_ALREADY_FOLLOWING
        )
        ;; Establish follow relationship
        (map-set following {
          follower: follower-id,
          following: following-id,
        } {
          followed-at: current-block,
          is-active: true,
        })
        ;; Update follower count
        (match (get-profile following-id)
          following-profile (map-set profiles { profile-id: following-id }
            (merge following-profile { follower-count: (+ (get follower-count following-profile) u1) })
          )
          false
        )
        ;; Update following count
        (match (get-profile follower-id)
          follower-profile (map-set profiles { profile-id: follower-id }
            (merge follower-profile { following-count: (+ (get following-count follower-profile) u1) })
          )
          false
        )
        (ok true)
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)

;; Unfollow a user
(define-public (unfollow-user (following-id uint))
  (let ((follower-profile-result (map-get? principal-to-profile tx-sender)))
    (match follower-profile-result
      follower-id (begin
        ;; Validate unfollow operation
        (asserts! (is-following follower-id following-id) ERR_NOT_FOLLOWING)
        ;; Remove follow relationship
        (map-delete following {
          follower: follower-id,
          following: following-id,
        })
        ;; Decrement follower count
        (match (get-profile following-id)
          following-profile (map-set profiles { profile-id: following-id }
            (merge following-profile { follower-count: (- (get follower-count following-profile) u1) })
          )
          false
        )
        ;; Decrement following count
        (match (get-profile follower-id)
          follower-profile (map-set profiles { profile-id: follower-id }
            (merge follower-profile { following-count: (- (get following-count follower-profile) u1) })
          )
          false
        )
        (ok true)
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)

;; CONTENT CREATION AND MONETIZATION

;; Publish new content
(define-public (create-post (content (string-utf8 500)))
  (let (
      (author-profile-result (map-get? principal-to-profile tx-sender))
      (post-id (var-get next-post-id))
      (current-block stacks-block-height)
    )
    (match author-profile-result
      author-id (begin
        ;; Create post record
        (map-set posts { post-id: post-id } {
          author: author-id,
          content: content,
          created-at: current-block,
          boosted-amount: u0,
          endorsement-count: u0,
          is-active: true,
        })
        ;; Update author's post count
        (match (get-profile author-id)
          author-profile (map-set profiles { profile-id: author-id }
            (merge author-profile { post-count: (+ (get post-count author-profile) u1) })
          )
          false
        )
        ;; Increment post counter
        (var-set next-post-id (+ post-id u1))
        (ok post-id)
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)

;; Amplify content with financial backing
(define-public (boost-post
    (post-id uint)
    (amount uint)
  )
  (let ((current-block stacks-block-height))
    ;; Validate boost parameters
    (asserts! (>= amount MIN_POST_BOOST) ERR_INVALID_AMOUNT)
    (asserts! (is-some (get-post post-id)) ERR_POST_NOT_FOUND)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    ;; Lock boost funds
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    ;; Record boost transaction
    (map-set post-boosts {
      post-id: post-id,
      booster: tx-sender,
    } {
      amount: amount,
      boosted-at: current-block,
    })
    ;; Update post boost total
    (match (get-post post-id)
      post-data (map-set posts { post-id: post-id }
        (merge post-data { boosted-amount: (+ (get boosted-amount post-data) amount) })
      )
      false
    )
    (ok true)
  )
)

;; REPUTATION AND ENDORSEMENT SYSTEM

;; Endorse content with stake
(define-public (endorse-post
    (post-id uint)
    (stake-amount uint)
  )
  (let (
      (endorser-profile-result (map-get? principal-to-profile tx-sender))
      (current-block stacks-block-height)
    )
    ;; Validate endorsement parameters
    (asserts! (>= stake-amount MIN_ENDORSEMENT_STAKE) ERR_INVALID_AMOUNT)
    (asserts! (is-some (get-post post-id)) ERR_POST_NOT_FOUND)
    (match endorser-profile-result
      endorser-id (begin
        ;; Prevent duplicate endorsements
        (asserts!
          (is-none (map-get? post-endorsements {
            post-id: post-id,
            endorser: endorser-id,
          }))
          ERR_ALREADY_ENDORSED
        )
        (asserts! (>= (stx-get-balance tx-sender) stake-amount)
          ERR_INSUFFICIENT_FUNDS
        )
        ;; Lock endorsement stake
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        ;; Record endorsement
        (map-set post-endorsements {
          post-id: post-id,
          endorser: endorser-id,
        } {
          endorsed-at: current-block,
          stake-amount: stake-amount,
        })
        ;; Update post endorsement count
        (match (get-post post-id)
          post-data (map-set posts { post-id: post-id }
            (merge post-data { endorsement-count: (+ (get endorsement-count post-data) u1) })
          )
          false
        )
        ;; Boost author's reputation
        (match (get-post post-id)
          post-data (match (get-profile (get author post-data))
            author-profile (map-set profiles { profile-id: (get author post-data) }
              (merge author-profile { total-endorsements: (+ (get total-endorsements author-profile) u1) })
            )
            false
          )
          false
        )
        (ok true)
      )
      ERR_PROFILE_NOT_FOUND
    )
  )
)