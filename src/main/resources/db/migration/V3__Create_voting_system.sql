/*
 * ============================================================================
 * Migration: V3__Create_voting_system.sql
 * Purpose: Create comprehensive voting and polling system with support for
 *          personal/channel choices, voting options, and vote tracking
 *
 * Author: Uvays Ramazanov
 * Version: 1.0
 * Created: 2025-10-27
 *
 * Dependencies:
 *   - V1__Create_users_and_groups.sql (users table)
 *   - V2__Create_channels.sql (channels table)
 *
 * Features:
 *   - Multi-choice polls with customizable options
 *   - Personal (private) or channel (public) choices
 *   - One vote per user per choice enforcement
 *   - Deadline-based voting periods
 *   - Choice lifecycle management (active, closed, archived)
 *   - Image support for visual choices
 *   - Position-based ordering for options
 *   - Comprehensive audit trail
 *
 * Use Cases:
 *   - Community polls and surveys
 *   - Decision-making tools
 *   - Feedback collection
 *   - Quiz systems
 *
 * ============================================================================
 */

-- ============================================================================
-- DOMAIN TYPES: Voting system validation
-- ============================================================================

/**
 * DOMAIN: valid_choice_title
 * Purpose: Choice question/title with length constraints
 * Rules:
 *   - Length: 5-100 characters
 *   - No leading/trailing whitespace
 *   - Must be meaningful (min 5 chars)
 *
 * Use Case: Poll questions, survey titles
 */
CREATE DOMAIN valid_choice_title AS VARCHAR(100)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 5 AND
        length(trim(VALUE)) <= 100 AND
        VALUE = trim(VALUE)
    );

/**
 * DOMAIN: valid_choice_description
 * Purpose: Detailed choice explanation
 * Rules:
 *   - Max length: 1000 characters
 *   - Nullable (optional context)
 *   - Trimmed
 *
 * Use Case: Poll context, survey instructions
 */
CREATE DOMAIN valid_choice_description AS TEXT
    CHECK (
        VALUE IS NULL OR
        (length(trim(VALUE)) >= 10 AND length(trim(VALUE)) <= 1000 AND VALUE = trim(VALUE))
    );

/**
 * DOMAIN: valid_option_text
 * Purpose: Individual voting option text
 * Rules:
 *   - Length: 1-100 characters
 *   - No leading/trailing whitespace
 *
 * Use Case: Poll answers, multiple choice options
 */
CREATE DOMAIN valid_option_text AS VARCHAR(100)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 1 AND
        length(trim(VALUE)) <= 100 AND
        VALUE = trim(VALUE)
        );

/**
 * ENUM: choice_status
 * Purpose: Track choice lifecycle
 *
 * States:
 *   - active: Accepting votes
 *   - closed: No longer accepting votes (manually closed)
 *   - archived: Historical record (auto-closed after deadline)
 */
CREATE TYPE choice_status AS ENUM (
    'active',
    'closed',
    'archived'
);

-- ============================================================================
-- TABLE: choices
-- ============================================================================
/**
 * TABLE: choices
 * Purpose: Core voting/polling entity representing questions or decisions
 *
 * Key Features:
 *   - Creator-owned (user who created the poll)
 *   - Optional channel association (public vs personal)
 *   - Deadline-based voting periods
 *   - Image support for visual polls
 *   - Status lifecycle (active → closed/archived)
 *
 * Access Control:
 *   - is_personal = TRUE: Only visible to creator
 *   - is_personal = FALSE + channel_id: Visible in channel
 *   - is_personal = FALSE + NULL channel: Public poll
 *
 * Validation:
 *   - Deadline must be in future when creating
 *   - Personal choices cannot have channel_id
 *
 * Indexes:
 *   - idx_choices_creator_id: User's choices
 *   - idx_choices_channel_id: Channel polls
 *   - idx_choices_status: Filter by state
 *   - idx_choices_deadline: Expiring polls
 */
CREATE TABLE choices (
    -- ========== Primary Key ==========
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Identity Information ==========
title valid_choice_title NOT NULL,
description valid_choice_description,
image BYTEA,

    -- ========== Ownership & Association ==========
creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
channel_id UUID REFERENCES channels(id) ON DELETE CASCADE,

    -- ========== Access Control ==========
is_personal BOOLEAN NOT NULL DEFAULT FALSE,

    -- ========== Lifecycle Management ==========
status choice_status NOT NULL DEFAULT 'active',
deadline TIMESTAMP,

    -- ========== Audit Timestamps ==========
created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Image validation
CHECK (image IS NULL OR octet_length(image) > 0),
CHECK (image IS NULL OR octet_length(image) <= 5242880), -- 5MB limit

    -- Personal choices cannot be in channels
CHECK (
    (is_personal = TRUE AND channel_id IS NULL) OR
    (is_personal = FALSE)
    ),

    -- Deadline must be in future (if set)
CHECK (deadline IS NULL OR deadline > created_at),

    -- Timestamp validation
CHECK (created_at <= CURRENT_TIMESTAMP),
CHECK (updated_at <= CURRENT_TIMESTAMP),
CHECK (updated_at >= created_at)
);

-- ============================================================================
-- TABLE: choice_options
-- ============================================================================
/**
 * TABLE: choice_options
 * Purpose: Individual voting options for each choice
 *
 * Key Features:
 *   - Multiple options per choice
 *   - Position-based ordering
 *   - Cascade delete with parent choice
 *
 * Constraints:
 *   - Position must be unique within a choice
 *   - Position must be >= 0
 *
 * Use Cases:
 *   - Multiple choice answers (A, B, C, D)
 *   - Poll options (Yes, No, Maybe)
 *   - Survey responses
 */
CREATE TABLE choice_options (
    -- ========== Primary Key ==========
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Association ==========
       choice_id UUID NOT NULL REFERENCES choices(id) ON DELETE CASCADE,

    -- ========== Option Content ==========
       text valid_option_text NOT NULL,
       position INTEGER NOT NULL,

    -- ========== Audit Timestamps ==========
       created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Position validation
       CHECK (position >= 0),
       CHECK (position < 1000), -- Reasonable limit

    -- Timestamp validation
       CHECK (created_at <= CURRENT_TIMESTAMP),

    -- Unique position per choice
       UNIQUE(choice_id, position)
);

-- ============================================================================
-- TABLE: votes
-- ============================================================================
/**
 * TABLE: votes
 * Purpose: Track individual user votes on choices
 *
 * Key Features:
 *   - One vote per user per choice (UNIQUE constraint)
 *   - Immutable once cast (no updates allowed via trigger)
 *   - Cascade delete with choice or user
 *
 * Constraints:
 *   - User can only vote once per choice
 *   - Vote option must belong to the choice
 *
 * Analytics:
 *   - voted_at for temporal analysis
 *   - Supports vote count aggregation
 *   - Vote distribution by option
 */
CREATE TABLE votes (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Association ==========
    choice_id UUID NOT NULL REFERENCES choices(id) ON DELETE CASCADE,
    choice_option_id UUID NOT NULL REFERENCES choice_options(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Audit Timestamps ==========
    voted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- One vote per user per choice
    UNIQUE(choice_id, user_id),

    -- Timestamp validation
    CHECK (voted_at <= CURRENT_TIMESTAMP)
);

-- ============================================================================
-- TABLE DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE choices IS
    'Voting and polling system. Supports personal (private) and channel (public) choices
     with optional deadlines, image attachments, and lifecycle management.';

COMMENT ON COLUMN choices.id IS 'Unique choice identifier (UUID v4)';
COMMENT ON COLUMN choices.title IS 'Choice question or poll title (5-500 chars)';
COMMENT ON COLUMN choices.description IS 'Optional detailed description or context (10-5000 chars)';
COMMENT ON COLUMN choices.image IS 'Optional image for visual polls (max 5MB)';
COMMENT ON COLUMN choices.creator_id IS 'User who created this choice (cascade delete)';
COMMENT ON COLUMN choices.channel_id IS 'Associated channel (NULL for personal choices)';
COMMENT ON COLUMN choices.is_personal IS 'TRUE = private choice, FALSE = public/channel choice';
COMMENT ON COLUMN choices.status IS 'Lifecycle state: active, closed, archived';
COMMENT ON COLUMN choices.deadline IS 'Optional voting deadline (automatically closes after)';

COMMENT ON TABLE choice_options IS
    'Individual voting options for choices. Position-ordered for consistent display.';

COMMENT ON COLUMN choice_options.text IS 'Option text (1-500 chars)';
COMMENT ON COLUMN choice_options.position IS 'Display order (0-indexed, unique per choice)';

COMMENT ON TABLE votes IS
    'Individual user votes. One vote per user per choice enforced by UNIQUE constraint.';

COMMENT ON COLUMN votes.voted_at IS 'Timestamp when vote was cast (immutable)';

COMMENT ON TYPE choice_status IS
    'Choice lifecycle: active (accepting votes), closed (manual close), archived (past deadline)';

-- ============================================================================
-- INDEXES: Query optimization
-- ============================================================================

-- Choices indexes
CREATE INDEX idx_choices_creator_id ON choices(creator_id);
COMMENT ON INDEX idx_choices_creator_id IS 'Find all choices created by a user';

CREATE INDEX idx_choices_channel_id ON choices(channel_id);
COMMENT ON INDEX idx_choices_channel_id IS 'Find all choices in a channel';

CREATE INDEX idx_choices_status ON choices(status);
COMMENT ON INDEX idx_choices_status IS 'Filter choices by lifecycle state';

CREATE INDEX idx_choices_deadline ON choices(deadline) WHERE deadline IS NOT NULL;
COMMENT ON INDEX idx_choices_deadline IS 'Partial index for choices with deadlines (auto-close queries)';

CREATE INDEX idx_choices_is_personal ON choices(is_personal, creator_id);
COMMENT ON INDEX idx_choices_is_personal IS 'Filter personal vs public choices';

CREATE INDEX idx_choices_created_at ON choices(created_at DESC);
COMMENT ON INDEX idx_choices_created_at IS 'Sort choices by creation date';

-- Choice options indexes
CREATE INDEX idx_choice_options_choice_id ON choice_options(choice_id);
COMMENT ON INDEX idx_choice_options_choice_id IS 'Retrieve all options for a choice';

CREATE INDEX idx_choice_options_position ON choice_options(choice_id, position);
COMMENT ON INDEX idx_choice_options_position IS 'Ordered retrieval of options';

-- Votes indexes
CREATE INDEX idx_votes_choice_id ON votes(choice_id);
COMMENT ON INDEX idx_votes_choice_id IS 'Aggregate votes for a choice';

CREATE INDEX idx_votes_choice_option_id ON votes(choice_option_id);
COMMENT ON INDEX idx_votes_choice_option_id IS 'Count votes per option';

CREATE INDEX idx_votes_user_id ON votes(user_id);
COMMENT ON INDEX idx_votes_user_id IS 'Find all votes by a user';

CREATE INDEX idx_votes_voted_at ON votes(voted_at DESC);
COMMENT ON INDEX idx_votes_voted_at IS 'Temporal analysis of voting patterns';

-- ============================================================================
-- FUNCTIONS: Business logic and validation
-- ============================================================================

/**
 * FUNCTION: validate_vote_option_belongs_to_choice()
 * Purpose: Ensure voted option belongs to the choice
 * Trigger: BEFORE INSERT ON votes
 *
 * Validation: The choice_option_id must belong to the choice_id
 */
CREATE OR REPLACE FUNCTION validate_vote_option_belongs_to_choice()
    RETURNS TRIGGER AS $$
DECLARE
    v_option_choice_id UUID;
BEGIN
    -- Get the choice_id for this option
    SELECT choice_id INTO v_option_choice_id
    FROM choice_options
    WHERE id = NEW.choice_option_id;

    -- Verify it matches
    IF v_option_choice_id IS NULL THEN
        RAISE EXCEPTION 'Invalid choice_option_id: option does not exist'
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_option_choice_id != NEW.choice_id THEN
        RAISE EXCEPTION 'Invalid vote: option does not belong to this choice'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'choice_option_id must belong to choice_id';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_vote_option_belongs_to_choice() IS
    'Ensures voted option belongs to the specified choice.';

/**
 * FUNCTION: validate_choice_is_active()
 * Purpose: Prevent voting on closed/archived choices
 * Trigger: BEFORE INSERT ON votes
 */
CREATE OR REPLACE FUNCTION validate_choice_is_active()
    RETURNS TRIGGER AS $$
DECLARE
    v_choice_status choice_status;
    v_choice_deadline TIMESTAMP;
BEGIN
    -- Get choice status and deadline
    SELECT status, deadline INTO v_choice_status, v_choice_deadline
    FROM choices
    WHERE id = NEW.choice_id;

    -- Check if choice is active
    IF v_choice_status != 'active'::choice_status THEN
        RAISE EXCEPTION 'Cannot vote on % choice', v_choice_status
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Only active choices accept votes';
    END IF;

    -- Check if deadline has passed
    IF v_choice_deadline IS NOT NULL AND v_choice_deadline < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Cannot vote: choice deadline has passed'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Deadline was at ' || v_choice_deadline;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_choice_is_active() IS
    'Prevents voting on closed, archived, or expired choices.';

/**
 * FUNCTION: prevent_vote_modification()
 * Purpose: Make votes immutable once cast
 * Trigger: BEFORE UPDATE ON votes
 */
CREATE OR REPLACE FUNCTION prevent_vote_modification()
    RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Votes cannot be modified once cast'
        USING ERRCODE = 'integrity_constraint_violation',
            HINT = 'Delete and re-vote if needed (if business rules allow)';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION prevent_vote_modification() IS
    'Enforces vote immutability: votes cannot be changed after casting.';

/**
 * FUNCTION: auto_close_expired_choices()
 * Purpose: Automatically archive choices past their deadline
 * Schedule: Run via cron job or scheduled task
 */
CREATE OR REPLACE FUNCTION auto_close_expired_choices()
    RETURNS INTEGER AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE choices
    SET status = 'archived'::choice_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE deadline IS NOT NULL
      AND deadline < CURRENT_TIMESTAMP
      AND status = 'active'::choice_status;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_close_expired_choices() IS
    'Batch function to archive expired choices. Should be called by scheduled job.';

/**
 * FUNCTION: update_updated_at()
 * Purpose: Auto-update timestamp on modifications
 */
CREATE OR REPLACE FUNCTION update_updated_at()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- TRIGGERS: Attach functions to tables
-- ============================================================================

-- Vote validation
CREATE TRIGGER votes_validate_option_belongs_to_choice
    BEFORE INSERT ON votes
    FOR EACH ROW EXECUTE FUNCTION validate_vote_option_belongs_to_choice();

CREATE TRIGGER votes_validate_choice_is_active
    BEFORE INSERT ON votes
    FOR EACH ROW EXECUTE FUNCTION validate_choice_is_active();

CREATE TRIGGER votes_prevent_modification
    BEFORE UPDATE ON votes
    FOR EACH ROW EXECUTE FUNCTION prevent_vote_modification();

-- Choice updates
CREATE TRIGGER choices_update_updated_at
    BEFORE UPDATE ON choices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- GRANTS: Role-based access control
-- ============================================================================
-- GRANT SELECT, INSERT ON choices TO app_user;
-- GRANT SELECT, INSERT ON choice_options TO app_user;
-- GRANT SELECT, INSERT ON votes TO app_user;
-- GRANT SELECT ON choices TO app_readonly;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================