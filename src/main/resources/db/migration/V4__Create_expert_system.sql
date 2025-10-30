/*
 * ============================================================================
 * Migration: V4__Create_stacks_system.sql
 * Purpose: Create stack/quiz management system and group membership
 *
 * Author: Uvays Ramazanov
 * Version: 1.0
 * Created: 2025-10-27
 *
 * Dependencies:
 *   - V1__Create_users_and_groups.sql (users, groups)
 *   - V3__Create_voting_system.sql (choices)
 *
 * Features:
 *   - Group membership (many-to-many users ↔ groups)
 *   - Stack/quiz creation and management
 *   - Position-based ordering of choices in stacks
 *   - Quiz mode support
 *   - Publishing workflow (draft → published)
 *
 * Use Cases:
 *   - Educational quizzes
 *   - Knowledge tests
 *   - Curated content collections
 *   - Learning paths
 *
 * ============================================================================
 */

-- ============================================================================
-- DOMAIN TYPES: Stack system validation
-- ============================================================================

/**
 * DOMAIN: valid_stack_title
 * Purpose: Stack title with meaningful constraints
 * Rules:
 *   - Length: 3-255 characters
 *   - No leading/trailing whitespace
 *
 * Use Case: Quiz titles, collection names
 */
CREATE DOMAIN valid_stack_title AS VARCHAR(255)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 3 AND
        length(trim(VALUE)) <= 255 AND
        VALUE = trim(VALUE)
        );

/**
 * DOMAIN: valid_stack_description
 * Purpose: Detailed stack explanation
 * Rules:
 *   - Max length: 5000 characters
 *   - Nullable (optional)
 *   - Trimmed
 *
 * Use Case: Quiz instructions, collection context
 */
CREATE DOMAIN valid_stack_description AS TEXT
    CHECK (
        VALUE IS NULL OR
        (length(trim(VALUE)) >= 10 AND length(trim(VALUE)) <= 5000 AND VALUE = trim(VALUE))
        );

-- ============================================================================
-- TABLE: group_users
-- ============================================================================
/**
 * TABLE: group_users
 * Purpose: Many-to-many relationship between users and groups
 *
 * Key Features:
 *   - Composite primary key (group_id, user_id)
 *   - Cascade delete on both sides
 *   - Efficient lookup in both directions
 *
 * Use Cases:
 *   - Group membership management
 *   - Permission checks
 *   - User discovery within groups
 *
 * Constraints:
 *   - User cannot join same group twice
 *   - Both user and group must exist
 */
CREATE TABLE group_users (
    -- ========== Composite Primary Key ==========
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Audit Timestamps ==========
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Primary Key Constraint ==========
    PRIMARY KEY (group_id, user_id),

    -- ========== Data Integrity Constraints ==========
    CHECK (joined_at <= CURRENT_TIMESTAMP)
);

-- ============================================================================
-- TABLE: stacks
-- ============================================================================
/**
 * TABLE: stacks
 * Purpose: Curated collections of choices (polls, quizzes, surveys)
 *
 * Key Features:
 *   - Creator-owned collections
 *   - Quiz mode for educational content
 *   - Publishing workflow (draft vs published)
 *   - Ordered items via stack_items table
 *
 * Workflow:
 *   1. Create stack (is_published = FALSE)
 *   2. Add items via stack_items
 *   3. Publish when ready (is_published = TRUE)
 *
 * Access Control:
 *   - Only creator can edit
 *   - Published stacks are visible to others
 *   - Unpublished stacks are private
 *
 * Use Cases:
 *   - Educational quizzes (is_quiz = TRUE)
 *   - Poll collections (is_quiz = FALSE)
 *   - Learning modules
 *   - Surveys with multiple questions
 */
CREATE TABLE stacks (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Identity Information ==========
    title valid_stack_title NOT NULL,
    description valid_stack_description,

    -- ========== Ownership ==========
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Stack Configuration ==========
    is_quiz BOOLEAN NOT NULL DEFAULT FALSE,
    is_published BOOLEAN NOT NULL DEFAULT FALSE,

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Published timestamp must be set when published
    CHECK (
        (is_published = TRUE AND published_at IS NOT NULL) OR
        (is_published = FALSE AND published_at IS NULL)
        ),

    -- Published timestamp cannot be before creation
    CHECK (published_at IS NULL OR published_at >= created_at),

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= created_at)
);

-- ============================================================================
-- TABLE: stack_items
-- ============================================================================
/**
 * TABLE: stack_items
 * Purpose: Ordered list of choices within a stack
 *
 * Key Features:
 *   - Position-based ordering
 *   - References choices from voting system
 *   - Cascade delete with stack
 *
 * Constraints:
 *   - Position must be unique within a stack
 *   - Position must be >= 0
 *   - Choice can appear multiple times in different stacks
 *   - Choice can appear only once per stack
 *
 * Use Cases:
 *   - Quiz questions in order
 *   - Survey flow
 *   - Content sequence
 */
CREATE TABLE stack_items (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Association ==========
    stack_id UUID NOT NULL REFERENCES stacks(id) ON DELETE CASCADE,
    choice_id UUID NOT NULL REFERENCES choices(id) ON DELETE CASCADE,

    -- ========== Ordering ==========
    position INTEGER NOT NULL,

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Position validation
    CHECK (position >= 0),
    CHECK (position < 10000), -- Reasonable limit

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),

    -- Unique position per stack
    UNIQUE(stack_id, position),

    -- Choice appears once per stack
    UNIQUE(stack_id, choice_id)
);

-- ============================================================================
-- TABLE DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE group_users IS
    'Many-to-many relationship table for group membership. Tracks which users belong to which groups.';

COMMENT ON COLUMN group_users.joined_at IS 'Timestamp when user joined the group';

COMMENT ON TABLE stacks IS
    'Curated collections of choices (polls, quizzes, surveys). Supports publishing workflow
     and quiz mode for educational content.';

COMMENT ON COLUMN stacks.title IS 'Stack title (3-255 chars)';
COMMENT ON COLUMN stacks.description IS 'Optional detailed description (10-5000 chars)';
COMMENT ON COLUMN stacks.creator_id IS 'User who created this stack (cascade delete)';
COMMENT ON COLUMN stacks.is_quiz IS 'TRUE = quiz mode (educational), FALSE = poll collection';
COMMENT ON COLUMN stacks.is_published IS 'TRUE = visible to others, FALSE = draft (private)';
COMMENT ON COLUMN stacks.published_at IS 'Timestamp when stack was published (NULL if unpublished)';

COMMENT ON TABLE stack_items IS
    'Ordered list of choices within stacks. Position-based for sequential display.';

COMMENT ON COLUMN stack_items.position IS 'Display order (0-indexed, unique per stack)';

-- ============================================================================
-- INDEXES: Query optimization
-- ============================================================================

-- Group users indexes
CREATE INDEX idx_group_users_group_id ON group_users(group_id);
COMMENT ON INDEX idx_group_users_group_id IS 'Find all users in a group';

CREATE INDEX idx_group_users_user_id ON group_users(user_id);
COMMENT ON INDEX idx_group_users_user_id IS 'Find all groups a user belongs to';

CREATE INDEX idx_group_users_joined_at ON group_users(joined_at DESC);
COMMENT ON INDEX idx_group_users_joined_at IS 'Recent group memberships';

-- Stacks indexes
CREATE INDEX idx_stacks_creator_id ON stacks(creator_id);
COMMENT ON INDEX idx_stacks_creator_id IS 'Find all stacks created by a user';

CREATE INDEX idx_stacks_is_published ON stacks(is_published, created_at DESC);
COMMENT ON INDEX idx_stacks_is_published IS 'Filter published stacks, sorted by creation';

CREATE INDEX idx_stacks_is_quiz ON stacks(is_quiz, is_published);
COMMENT ON INDEX idx_stacks_is_quiz IS 'Filter quizzes vs poll collections';

CREATE INDEX idx_stacks_published_at ON stacks(published_at DESC) WHERE published_at IS NOT NULL;
COMMENT ON INDEX idx_stacks_published_at IS 'Partial index for recently published stacks';

CREATE INDEX idx_stacks_created_at ON stacks(created_at DESC);
COMMENT ON INDEX idx_stacks_created_at IS 'Sort stacks by creation date';

-- Stack items indexes
CREATE INDEX idx_stack_items_stack_id ON stack_items(stack_id, position);
COMMENT ON INDEX idx_stack_items_stack_id IS 'Retrieve ordered items for a stack';

CREATE INDEX idx_stack_items_choice_id ON stack_items(choice_id);
COMMENT ON INDEX idx_stack_items_choice_id IS 'Find which stacks contain a choice';

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================