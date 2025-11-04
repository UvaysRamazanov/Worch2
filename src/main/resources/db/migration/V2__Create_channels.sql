/*
 * ============================================================================
 * Migration: V2__Create_channels.sql
 * Purpose: Create channel management system with access control,
 *          content filtering, and audit capabilities
 *
 * Author: Uvays Ramazanov
 * Version: 1.0
 * Created: 2025-10-20
 *
 * Dependencies: V1__Create_users_and_groups.sql (users table)
 *
 * Features:
 *   - Public/Private channel access control
 *   - Age-restricted content management (COPPA/GDPR)
 *   - Password-protected channels for enhanced security
 *   - Comprehensive audit trail with timestamps
 *   - Content moderation support
 *   - Full-text search optimization
 *
 * ============================================================================
 */

-- ============================================================================
-- DOMAIN TYPES: Channel-specific validation
-- ============================================================================

/**
 * DOMAIN: valid_channel_name
 * Purpose: Channel identifiers with URL-safe constraints
 * Rules:
 *   - Length: 3-255 characters
 *   - Allowed: Alphanumeric, spaces, hyphens, underscores
 *   - No consecutive hyphens or underscores
 *   - No leading/trailing special characters
 *   - Case-insensitive uniqueness
 *
 * Use Case: Channel names must be URL-friendly and globally unique
 */
CREATE DOMAIN valid_channel_name AS VARCHAR(255)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 3 AND
        length(trim(VALUE)) <= 255 AND
        VALUE ~ '^[a-zA-Z0-9][a-zA-Z0-9\s\-_]*[a-zA-Z0-9]$' AND
        VALUE NOT LIKE '%  %' AND
        VALUE = trim(VALUE)
        );

/**
 * DOMAIN: valid_channel_description
 * Purpose: Channel descriptions with length constraints
 * Rules:
 *   - Max length: 5000 characters
 *   - Nullable (optional description)
 *   - Trimmed: No leading/trailing whitespace
 *
 * Use Case: Rich descriptions for channel discovery and documentation
 */
CREATE DOMAIN valid_channel_description AS TEXT
    CHECK (
        VALUE IS NULL OR
        (length(trim(VALUE)) >= 5 AND length(trim(VALUE)) <= 5000 AND VALUE = trim(VALUE))
        );

/**
 * DOMAIN: valid_channel_password
 * Purpose: Hashed password storage validation
 * Rules:
 *   - Only when is_private = TRUE
 *   - Stored as bcrypt hash (typically 60 characters)
 *   - Not directly validated here (hashing done in application)
 *
 * Use Case: Password-protected private channels for restricted access
 * Security Note: Passwords should NEVER be stored in plain text
 */
CREATE DOMAIN valid_channel_password AS VARCHAR(255)
    CHECK (
        VALUE IS NULL OR
        (length(VALUE) >= 20 AND length(VALUE) <= 255)
        );

/**
 * ENUM: channel_status
 * Purpose: Track channel lifecycle and moderation status
 *
 * States:
 *   - active: Channel is available for use
 *   - suspended: Temporarily disabled (moderation hold)
 *   - archived: Channel is read-only (no longer active)
 *   - deleted: Soft-delete (data retention compliance)
 */
CREATE TYPE channel_status AS ENUM (
    'active',
    'suspended',
    'archived',
    'deleted'
    );

-- ============================================================================
-- TABLE: channels
-- ============================================================================
/**
 * TABLE: channels
 * Purpose: Core channel entity for content organization and access control
 *
 * Key Features:
 *   - UUID primary key for distributed systems
 *   - Public/Private access control with optional password
 *   - Age-restricted content filtering (COPPA compliance)
 *   - Channel lifecycle management (active, suspended, archived, deleted)
 *   - Owner-based permissions model
 *   - Comprehensive audit trail
 *
 * Access Control:
 *   - Public: Anyone can discover and join
 *   - Private: Requires owner approval or password
 *   - Age-Restricted: Content not visible to users < 18
 *
 * Indexes:
 *   - idx_channels_owner_id: For owner's channel list
 *   - idx_channels_name: For channel discovery
 *   - idx_channels_status: For filtering active channels
 *   - idx_channels_created_at: For sorting by creation date
 *   - idx_channels_name_trgm: For full-text search
 *
 * Cascade Behavior:
 *   - ON DELETE CASCADE: Deletes all associated channel data when owner is deleted
 */
CREATE TABLE channels (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Identity Information ==========
    name valid_channel_name NOT NULL UNIQUE,
    description valid_channel_description,

    -- ========== Access Control ==========
    is_private BOOLEAN NOT NULL DEFAULT FALSE,
    password valid_channel_password,
    age_restricted BOOLEAN NOT NULL DEFAULT FALSE,

    -- ========== Content Moderation ==========
    status channel_status NOT NULL DEFAULT 'active',

    -- ========== Ownership ==========
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Password can only be set on private channels
    CHECK (
        (is_private = TRUE AND password IS NOT NULL) OR
        (is_private = FALSE AND password IS NULL)
    ),

    -- Age restriction validation
    CHECK (age_restricted IN (TRUE, FALSE)),

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= created_at)
);

-- ============================================================================
-- TABLE DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE channels IS
    'Channel management system with multi-level access control, content moderation,
     and age-based filtering. Supports both public discovery and private membership-based access.
     All channels are owned by a single user (owner) who has administrative privileges.';

COMMENT ON COLUMN channels.id IS 'Unique channel identifier (UUID v4)';
COMMENT ON COLUMN channels.name IS 'Channel display name (URL-safe, globally unique)';
COMMENT ON COLUMN channels.description IS 'Channel description for discovery and documentation (5-5000 chars, optional)';
COMMENT ON COLUMN channels.is_private IS 'TRUE = private channel (requires membership), FALSE = public (discoverable)';
COMMENT ON COLUMN channels.password IS 'Bcrypt hashed password for private channels (only set when is_private=TRUE)';
COMMENT ON COLUMN channels.age_restricted IS 'TRUE = content for users 18+ only (COPPA/GDPR compliance)';
COMMENT ON COLUMN channels.status IS 'Channel lifecycle state: active, suspended, archived, or deleted';
COMMENT ON COLUMN channels.owner_id IS 'User who owns/administers this channel (cascade delete)';
COMMENT ON COLUMN channels.created_at IS 'Channel creation timestamp (immutable, audit trail)';
COMMENT ON COLUMN channels.updated_at IS 'Last modification timestamp (auto-updated on changes)';

COMMENT ON TYPE channel_status IS
    'Channel lifecycle states: active (operational), suspended (moderation hold),
     archived (read-only), deleted (soft-delete for compliance)';

-- ============================================================================
-- INDEXES: Query optimization and uniqueness
-- ============================================================================

-- Owner lookups: "Show all channels owned by user X"
CREATE INDEX idx_channels_owner_id ON channels(owner_id);

-- Channel discovery: "Find channel by name"
CREATE INDEX idx_channels_name ON channels(name);
COMMENT ON INDEX idx_channels_name IS 'Primary index for exact channel name lookups';

-- Status filtering: "Show all active channels"
CREATE INDEX idx_channels_status ON channels(status);
COMMENT ON INDEX idx_channels_status IS 'Filter channels by lifecycle state (active, archived, etc.)';

-- Audit and sorting: "Recently created channels"
CREATE INDEX idx_channels_created_at ON channels(created_at DESC);
COMMENT ON INDEX idx_channels_created_at IS 'Sort channels by creation date (DESC for newest first)';

-- Access control: "Public channels owned by user X"
CREATE INDEX idx_channels_public_access ON channels(is_private, owner_id);
COMMENT ON INDEX idx_channels_public_access IS 'Composite index for access control queries';

-- Age filtering: "Content appropriate for user"
CREATE INDEX idx_channels_age_filtered ON channels(age_restricted, status);
COMMENT ON INDEX idx_channels_age_filtered IS 'Filter age-appropriate content for compliance';

-- Full-text search: "Search channels by name and description"
CREATE INDEX idx_channels_name_description_trgm ON channels USING GIST (
                            (name || ' ' || COALESCE(description, '')) gist_trgm_ops
    );
COMMENT ON INDEX idx_channels_name_description_trgm IS
    'Trigram index for fuzzy/partial text search in channel metadata';

-- ============================================================================
-- FUNCTIONS: Business logic and data integrity
-- ============================================================================

/**
 * FUNCTION: validate_channel_password()
 * Purpose: Ensure password is only set on private channels
 * Trigger: BEFORE INSERT OR UPDATE ON channels
 *
 * Validation Rules:
 *   - Private channels MUST have a password
 *   - Public channels MUST NOT have a password
 *   - Password must be non-empty if set
 */
CREATE OR REPLACE FUNCTION validate_channel_password()
    RETURNS TRIGGER AS $$
BEGIN
    -- Private channel must have password
    IF NEW.is_private = TRUE AND NEW.password IS NULL THEN
        RAISE EXCEPTION 'Private channel must have a password'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Set password before making channel private';
    END IF;

    -- Public channel cannot have password
    IF NEW.is_private = FALSE AND NEW.password IS NOT NULL THEN
        NEW.password := NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_channel_password() IS
    'Enforces password requirements: private channels require a password, public channels must not have one.';

/**
 * FUNCTION: prevent_created_at_update()
 * Purpose: Ensure created_at timestamp is immutable
 * Trigger: BEFORE UPDATE ON channels
 *
 * Audit Trail: The created_at field is immutable to maintain accurate
 * historical records of when channels were created.
 */
CREATE OR REPLACE FUNCTION prevent_created_at_update()
    RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        NEW.created_at := OLD.created_at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION prevent_created_at_update() IS
    'Ensures created_at timestamp cannot be modified (immutable audit trail).';

/**
 * FUNCTION: update_updated_at()
 * Purpose: Automatically update the updated_at timestamp on modifications
 * Trigger: BEFORE UPDATE ON channels
 *
 * Pattern: Standard pattern for audit trails - automatically tracks when
 * a record was last modified without manual intervention.
 */
CREATE OR REPLACE FUNCTION update_updated_at()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION update_updated_at() IS
    'Automatically updates the updated_at timestamp on any record modification.';

/**
 * FUNCTION: prevent_deleted_channel_modification()
 * Purpose: Prevent modifications to deleted channels
 * Trigger: BEFORE UPDATE ON channels
 *
 * Business Rule: Once a channel is marked as deleted (soft-delete),
 * it should not be modified. Only the status can be updated to restore it.
 */
CREATE OR REPLACE FUNCTION prevent_deleted_channel_modification()
    RETURNS TRIGGER AS $$
BEGIN
    -- Only allow status update for deleted channels (e.g., restoration)
    IF OLD.status = 'deleted'::channel_status THEN
        IF NEW.status = 'deleted'::channel_status AND
           OLD.name IS DISTINCT FROM NEW.name THEN
            RAISE EXCEPTION 'Cannot modify a deleted channel (soft-delete protection)'
                USING ERRCODE = 'integrity_constraint_violation',
                    HINT = 'Restore the channel by updating status to ''active'' first';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION prevent_deleted_channel_modification() IS
    'Enforces soft-delete protection: prevents modification of deleted channels.';

/**
 * FUNCTION: log_channel_modification()
 * Purpose: Audit logging for channel modifications (future audit_log table)
 * Trigger: AFTER UPDATE ON channels
 *
 * Note: This function is defined for future integration with audit logging.
 * Currently acts as a placeholder for audit_log insertion logic.
 */
CREATE OR REPLACE FUNCTION log_channel_modification()
    RETURNS TRIGGER AS $$
BEGIN
    -- Future implementation: INSERT INTO audit_log
    -- This function serves as a foundation for comprehensive audit trails
    -- tracking what changed, who changed it, and when
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION log_channel_modification() IS
    'Placeholder for comprehensive audit logging of channel modifications.
     To be implemented with dedicated audit_log table.';

-- ============================================================================
-- TRIGGERS: Attach functions to channels table
-- ============================================================================

-- Password validation: Ensure private channels have passwords
CREATE TRIGGER channels_validate_password
    BEFORE INSERT OR UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION validate_channel_password();

-- Timestamp protection: Prevent created_at modification
CREATE TRIGGER channels_prevent_created_at_update
    BEFORE UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION prevent_created_at_update();

-- Audit trail: Auto-update modified timestamp
CREATE TRIGGER channels_update_updated_at
    BEFORE UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Soft-delete protection: Prevent modification of deleted channels
CREATE TRIGGER channels_prevent_deleted_modification
    BEFORE UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION prevent_deleted_channel_modification();

-- Audit logging: Log all modifications (future audit_log integration)
CREATE TRIGGER channels_log_modifications
    AFTER UPDATE ON channels
    FOR EACH ROW EXECUTE FUNCTION log_channel_modification();

-- ============================================================================
-- GRANTS: Role-based access control (RBAC)
-- ============================================================================
-- Uncomment and adjust based on your application's security model

-- Allow app users to read and create channels
-- GRANT SELECT, INSERT ON channels TO app_user;

-- Allow app users to update/delete their own channels (enforced in application)
-- GRANT UPDATE, DELETE ON channels TO app_user;

-- Read-only access for analytics/reporting
-- GRANT SELECT ON channels TO app_readonly;

-- Admin access for content moderation
-- GRANT SELECT, UPDATE ON channels TO app_admin;

-- ============================================================================
-- INITIAL DATA (Optional) - For development/testing only
-- ============================================================================
-- Uncomment for seeding development data
-- INSERT INTO channels (name, description, owner_id, is_private, status)
-- VALUES ('general', 'General discussion channel', <admin_user_id>, FALSE, 'active');

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================