# ── Users ────────────────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "users" {
  name         = "${local.prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Posts ────────────────────────────────────────────────────────────────────
# PK: postId. GSI byAuthor lists a user's finds for the profile grid; GSI byFeed
# (PK feedPk, SK createdAt) is the recency-ordered global-feed index the /feed
# endpoint + Maxi's catalog cache page through (no full-table scan); GSI byCategory
# (PK category, SK createdAt) gives Maxi a deep, recency-ordered pool per category.
resource "aws_dynamodb_table" "posts" {
  name         = "${local.prefix}-posts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "postId"

  attribute {
    name = "postId"
    type = "S"
  }
  attribute {
    name = "author"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "N"
  }
  # Partition key for the global feed index. Defaults to a single "all" partition;
  # set var.feed_shards > 1 to spread writes across "all#<n>" + scatter-gather
  # reads once the feed exceeds GSI partition throughput (~3k RCU/s). The key
  # SCHEMA is unchanged by sharding — only the values written — so no GSI rebuild.
  attribute {
    name = "feedPk"
    type = "S"
  }
  # Category partition key for the byCategory GSI (sparse: only posts that carry a
  # `category` are indexed). Powers Maxi's per-category find_gifts / find_deals.
  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "byAuthor"
    hash_key        = "author"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byFeed"
    hash_key        = "feedPk"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byCategory"
    hash_key        = "category"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── UGC reports ──────────────────────────────────────────────────────────────
# Reports are separate from feed interactions so moderation operations can
# query a post's open reports without scanning user partitions.
resource "aws_dynamodb_table" "ugc_reports" {
  name         = "${local.prefix}-ugc-reports"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "reportId"

  attribute {
    name = "reportId"
    type = "S"
  }
  attribute {
    name = "postId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "N"
  }

  global_secondary_index {
    name            = "byPost"
    hash_key        = "postId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery { enabled = true }
}

# ── Knowledge ────────────────────────────────────────────────────────────────
# Gift-knowledge base mined from Reddit discussions. PK: recipient (mom, couple,
# coworker, ...). Each item holds ranked gift ideas + co-occurrence bundles.
resource "aws_dynamodb_table" "knowledge" {
  name         = "${local.prefix}-knowledge"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "recipient"

  attribute {
    name = "recipient"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Events ────────────────────────────────────────────────────────────────────
# Unified event store (formerly "milestones"). PK: userId, SK: eventId. Holds
# everything we capture from onboarding onward, tagged by `scope`:
#   • personal — self milestones / the user's own occasions
#   • shared   — recipients' occasions + soft-profile birthdays from challenges
# GSI byScope lists a user's personal vs shared events directly.
resource "aws_dynamodb_table" "events" {
  name         = "${local.prefix}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "eventId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "eventId"
    type = "S"
  }
  attribute {
    name = "scope"
    type = "S"
  }

  global_secondary_index {
    name            = "byScope"
    hash_key        = "userId"
    range_key       = "scope"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Graph (network graph: nodes + edges) ──────────────────────────────────────
# Single-table adjacency model capturing ALL data (hard onboarding data + soft
# swipe-derived taste) as one connected graph so nothing is lost. Partitioned by
# owner (userId) so a user's whole subgraph loads in one Query; the byEntity GSI
# enables cross-owner traversal of edges into any node.
#   pk       = userId (owner of the subgraph)
#   sk       = "N#<type>#<id>" (node)  |  "E#<rel>#<src>#<dst>" (edge)
#   entityId = "<type>#<id>"  (a node's self-ref, or an edge's destination ref)
resource "aws_dynamodb_table" "graph" {
  name         = "${local.prefix}-graph"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }

  global_secondary_index {
    name            = "byEntity"
    hash_key        = "entityId"
    range_key       = "sk"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Interactions ─────────────────────────────────────────────────────────────
# PK: userId, SK: targetId (e.g. "post#p1"). One row per (user, target) so
# likes/saves are naturally idempotent. `type` holds like|save|comment.
resource "aws_dynamodb_table" "interactions" {
  name         = "${local.prefix}-interactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "targetId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "targetId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Connections (soft profiles) ───────────────────────────────────────────────
# Soft profiles collected when an invited guest finishes the swipe challenge.
# PK: userId (the SENDER's Clerk userId), SK: connectionId. Unseen rows double as
# the sender's "X completed your challenge" notifications. Consent is implied by
# the guest completing a link the sender shared (see the web app's /privacy).
resource "aws_dynamodb_table" "connections" {
  name         = "${local.prefix}-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "connectionId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "connectionId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Challenges (product-seeded swipe challenges) ──────────────────────────────
# A challenge = a seed product/image + a server-built swipe deck of similar
# catalog items (S3 Vectors kNN), sent to a friend. Single-table adjacency:
#   pk = challengeId
#   sk = "META"                → the challenge (senderId, seed, deck, verdictable)
#        "RESP#<ts>#<id>"      → one guest response (swipes + computed verdict)
# GSI bySender (sparse: only META rows carry senderId) lists a sender's
# challenges newest-first, mirroring the connections claim flow for anon ids.
resource "aws_dynamodb_table" "challenges" {
  name         = "${local.prefix}-challenges"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "challengeId"
  range_key    = "itemId"

  attribute {
    name = "challengeId"
    type = "S"
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  attribute {
    name = "senderId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "N"
  }

  global_secondary_index {
    name            = "bySender"
    hash_key        = "senderId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Friends (social graph + 1:1 DMs) ───────────────────────────────────────────
# Hard friend connections between signed-in accounts (distinct from soft-profile
# `connections` collected via swipe challenges). Single-table adjacency:
#   pk = userId, sk = "FRIEND#<otherId>"  → pending|accepted edge (mirrored)
#   pk = userId, sk = "DM#<threadId>"     → DM inbox pointer (lastText/lastAt)
#   pk = "DM#<sortedPair>", sk = "META" | "MSG#<ts>#<id>"  → conversation
# People discovery itself reads the users table (public profiles only).
resource "aws_dynamodb_table" "friends" {
  name         = "${local.prefix}-friends"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Pools (group gifts) ───────────────────────────────────────────────────────
# Backend-backed group-gift pools so contributions + the group chat sync across
# everyone in the pool (the old localStorage pools were per-device only).
# Single-table adjacency keyed by the pool:
#   pk = poolId
#   sk = "META"                    → the pool record (title/goal/raised/organizer…)
#        "MEMBER#<userId>"         → a member (memberId, name, joinedAt, role)
#        "CONTRIB#<ts>#<id>"       → a contribution (userId, name, amount, at)
#        "MSG#<ts>#<id>"           → a group-chat message (userId, name, text, at)
# So one Query(pk=poolId) returns the whole pool; a begins_with(sk,"MSG#") query
# pages just the chat. GSI byMember (sparse: only MEMBER rows carry memberId)
# lists every pool a given user belongs to for the "my group gifts" list.
resource "aws_dynamodb_table" "pools" {
  name         = "${local.prefix}-pools"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "poolId"
  range_key    = "itemId"

  attribute {
    name = "poolId"
    type = "S"
  }
  attribute {
    name = "itemId"
    type = "S"
  }
  attribute {
    name = "memberId"
    type = "S"
  }
  attribute {
    name = "joinedAt"
    type = "N"
  }

  global_secondary_index {
    name            = "byMember"
    hash_key        = "memberId"
    range_key       = "joinedAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}
