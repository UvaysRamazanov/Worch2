/*
 * ============================================================================
 * Migration: V5__Create_expert_system.sql
 * Purpose: Create expert profile and application management system
 *
 * Author: Uvays Ramazanov
 * Version: 1.0
 * Created: 2025-10-27
 *
 * Dependencies:
 *   - V1__Create_users_and_groups.sql (users table)
 *
 * Features:
 *   - Expert application workflow (NEW → IN_PROGRESS → APPROVED/REJECTED)
 *   - Expert profile with pricing and ratings
 *   - Incognito mode for anonymous expertise
 *   - Rating system (0.0 - 5.0 scale)
 *   - Application status tracking with timestamps
 *
 * Business Rules:
 *   - Users must apply to become experts
 *   - Only approved applications create expert profiles
 *   - Experts can set their own pricing
 *   - Ratings are calculated externally and stored here
 *
 * Use Cases:
 *   - Expert consultation marketplace
 *   - Professional advice platform
 *   - Skill-based matching
 *   - Premium content access
 *
 * ============================================================================
 */

-- ============================================================================
-- DOMAIN TYPES: Expert system validation
-- ============================================================================

/**
 * DOMAIN: valid_motivation_text
 * Purpose: Expert application motivation with meaningful content
 * Rules:
 *   - Length: 50-5000 characters
 *   - Must provide substantial reasoning
 *   - Trimmed
 *
 * Use Case: Expert application essays, qualification descriptions
 */
CREATE DOMAIN valid_motivation_text AS TEXT
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 50 AND
        length(trim(VALUE)) <= 5000 AND
        VALUE = trim(VALUE)
        );

/**
 * DOMAIN: valid_expert_price
 * Purpose: Expert consultation pricing
 * Rules:
 *   - Must be positive (> 0)
 *   - Reasonable maximum (1,000,000)
 *   - Integer value (smallest currency unit, e.g., cents)
 *
 * Use Case: Hourly rates, per-session pricing
 * Note: Store in smallest currency unit (cents, kopeks, etc.)
 */
CREATE DOMAIN valid_expert_price AS INTEGER
    CHECK (
        VALUE > 0 AND
        VALUE <= 1000000
        );

/**
 * DOMAIN: valid_expert_rating
 * Purpose: Expert rating score
 * Rules:
 *   - Range: 0.00 - 5.00
 *   - Two decimal places precision
 *   - Default: 0.00 (no ratings yet)
 *
 * Use Case: Average rating from user reviews
 */
CREATE DOMAIN valid_expert_rating AS NUMERIC(3, 2)
    CHECK (
        VALUE >= 0.00 AND
        VALUE <= 5.00
        );

/**
 * ENUM: application_status
 * Purpose: Track expert application lifecycle
 *
 * States:
 *   - NEW: Application submitted, awaiting review
 *   - IN_PROGRESS: Under review by admin/moderator
 *   - APPROVED: Application accepted, expert profile created
 *   - REJECTED: Application denied (with reason in future audit table)
 *
 * Workflow:
 *   NEW → IN_PROGRESS → {APPROVED | REJECTED}
 */
CREATE TYPE application_status AS ENUM (
    'NEW',
    'IN_PROGRESS',
    'APPROVED',
    'REJECTED'
    );

-- ============================================================================
-- TABLE: expert_applications
-- ============================================================================
/**
 * TABLE: expert_applications
 * Purpose: Track expert application submissions and approval workflow
 *
 * Key Features:
 *   - User-submitted applications
 *   - Status-based workflow
 *   - Motivation essay for qualification review
 *   - Audit trail with submission timestamp
 *
 * Workflow:
 *   1. User submits application (status = NEW)
 *   2. Admin reviews (status = IN_PROGRESS)
 *   3. Decision made (status = APPROVED or REJECTED)
 *   4. If APPROVED → expert_profiles entry created
 *
 * Business Rules:
 *   - User can have multiple applications (reapply if rejected)
 *   - Only most recent application status matters
 *   - Approved applications are immutable
 *
 * Indexes:
 *   - idx_expert_applications_user_id: User's application history
 *   - idx_expert_applications_status: Filter by state
 *   - idx_expert_applications_submitted_at: Sort by date
 */
CREATE TABLE expert_applications (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Applicant Information ==========
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Application Content ==========
    motivation valid_motivation_text NOT NULL,

    -- ========== Workflow Status ==========
    status application_status NOT NULL DEFAULT 'NEW',

    -- ========== Audit Timestamps ==========
    submitted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Reviewed timestamp only when not NEW
    CHECK (
        (status = 'NEW' AND reviewed_at IS NULL) OR
        (status != 'NEW' AND reviewed_at IS NOT NULL)
        ),

    -- Reviewed timestamp must be after submission
    CHECK (reviewed_at IS NULL OR reviewed_at >= submitted_at),

    -- Timestamp validation
    CHECK (submitted_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= submitted_at)
);

-- ============================================================================
-- TABLE: expert_profiles
-- ============================================================================
/**
 * TABLE: expert_profiles
 * Purpose: Expert user profiles with pricing and reputation
 *
 * Key Features:
 *   - One profile per user (UNIQUE constraint)
 *   - Custom pricing per expert
 *   - Rating system for reputation
 *   - Incognito mode for anonymous expertise
 *
 * Creation:
 *   - Only created after application approval
 *   - Initial rating is 0.00 (no reviews yet)
 *   - Expert sets initial price
 *
 * Business Rules:
 *   - User can only have one expert profile
 *   - Profile persists even if later applications are rejected
 *   - Ratings are updated externally (reviews table in future)
 *
 * Indexes:
 *   - idx_expert_profiles_user_id: Lookup by user
 *   - idx_expert_profiles_rating: Sort by reputation
 *   - idx_expert_profiles_price: Filter by price range
 */
CREATE TABLE expert_profiles (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Expert User ==========
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- ========== Profile Settings ==========
    is_incognito BOOLEAN NOT NULL DEFAULT FALSE,

    -- ========== Pricing ==========
    price valid_expert_price NOT NULL,

    -- ========== Reputation ==========
    rating valid_expert_rating DEFAULT 0.00,
    review_count INTEGER NOT NULL DEFAULT 0,

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Review count must be non-negative
    CHECK (review_count >= 0),

    -- Rating of 0.00 only if no reviews
    CHECK (
        (review_count = 0 AND rating = 0.00) OR
        (review_count > 0 AND rating > 0.00)
        ),

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= created_at)
);

-- ============================================================================
-- TABLE DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE expert_applications IS
    'Expert application workflow system. Tracks submissions from users requesting expert status,
     approval process, and decision outcomes.';

COMMENT ON COLUMN expert_applications.id IS 'Unique application identifier (UUID v4)';
COMMENT ON COLUMN expert_applications.user_id IS 'User submitting the application (cascade delete)';
COMMENT ON COLUMN expert_applications.motivation IS 'Expert qualification essay (50-5000 chars)';
COMMENT ON COLUMN expert_applications.status IS 'Application state: NEW, IN_PROGRESS, APPROVED, REJECTED';
COMMENT ON COLUMN expert_applications.submitted_at IS 'Application submission timestamp (immutable)';
COMMENT ON COLUMN expert_applications.reviewed_at IS 'When application was reviewed (NULL if pending)';

COMMENT ON TABLE expert_profiles IS
    'Expert user profiles with pricing, ratings, and settings. Created only after application approval.
     One profile per user with reputation tracking.';

COMMENT ON COLUMN expert_profiles.id IS 'Unique expert profile identifier (UUID v4)';
COMMENT ON COLUMN expert_profiles.user_id IS 'Associated user (one-to-one, unique)';
COMMENT ON COLUMN expert_profiles.is_incognito IS 'TRUE = anonymous expertise, FALSE = public profile';
COMMENT ON COLUMN expert_profiles.price IS 'Consultation price in smallest currency unit (e.g., cents)';
COMMENT ON COLUMN expert_profiles.rating IS 'Average rating from reviews (0.00-5.00, two decimals)';
COMMENT ON COLUMN expert_profiles.review_count IS 'Total number of reviews received';

COMMENT ON TYPE application_status IS
    'Expert application workflow states: NEW (submitted), IN_PROGRESS (under review),
     APPROVED (accepted), REJECTED (denied)';

-- ============================================================================
-- INDEXES: Query optimization
-- ============================================================================

-- Expert applications indexes
CREATE INDEX idx_expert_applications_user_id ON expert_applications(user_id, submitted_at DESC);
COMMENT ON INDEX idx_expert_applications_user_id IS 'User application history, sorted by submission date';

CREATE INDEX idx_expert_applications_status ON expert_applications(status, submitted_at DESC);
COMMENT ON INDEX idx_expert_applications_status IS 'Filter applications by status (admin review queue)';

CREATE INDEX idx_expert_applications_submitted_at ON expert_applications(submitted_at DESC);
COMMENT ON INDEX idx_expert_applications_submitted_at IS 'Sort all applications by submission date';

CREATE INDEX idx_expert_applications_reviewed_at ON expert_applications(reviewed_at DESC)
    WHERE reviewed_at IS NOT NULL;
COMMENT ON INDEX idx_expert_applications_reviewed_at IS 'Partial index for reviewed applications only';

-- Expert profiles indexes
CREATE INDEX idx_expert_profiles_user_id ON expert_profiles(user_id);
COMMENT ON INDEX idx_expert_profiles_user_id IS 'Lookup expert profile by user';

CREATE INDEX idx_expert_profiles_rating ON expert_profiles(rating DESC, review_count DESC);
COMMENT ON INDEX idx_expert_profiles_rating IS 'Sort experts by rating and review count';

CREATE INDEX idx_expert_profiles_price ON expert_profiles(price ASC);
COMMENT ON INDEX idx_expert_profiles_price IS 'Sort experts by price (budget filtering)';

CREATE INDEX idx_expert_profiles_incognito ON expert_profiles(is_incognito, rating DESC)
    WHERE is_incognito = FALSE;
COMMENT ON INDEX idx_expert_profiles_incognito IS 'Partial index for public expert discovery';

-- ============================================================================
-- FUNCTIONS: Business logic and validation
-- ============================================================================

/**
 * FUNCTION: create_expert_profile_on_approval()
 * Purpose: Automatically create expert profile when application is approved
 * Trigger: AFTER UPDATE ON expert_applications
 *
 * Business Logic:
 *   - Triggered when status changes to APPROVED
 *   - Creates expert_profiles entry if doesn't exist
 *   - Sets default price (can be updated later)
 *   - Initial rating is 0.00
 */
CREATE OR REPLACE FUNCTION create_expert_profile_on_approval()
    RETURNS TRIGGER AS $$
BEGIN
    -- Only act when status changes to APPROVED
    IF NEW.status = 'APPROVED'::application_status AND
       OLD.status != 'APPROVED'::application_status THEN

        -- Create expert profile if doesn't exist
        INSERT INTO expert_profiles (user_id, price, rating, review_count)
        VALUES (NEW.user_id, 10000, 0.00, 0) -- Default: 100.00 in base currency
        ON CONFLICT (user_id) DO NOTHING; -- Already exists, skip

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_expert_profile_on_approval() IS
    'Automatically creates expert profile when application is approved.';

/**
 * FUNCTION: prevent_approved_application_modification()
 * Purpose: Lock approved applications (immutable once approved)
 * Trigger: BEFORE UPDATE ON expert_applications
 */
CREATE OR REPLACE FUNCTION prevent_approved_application_modification()
    RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'APPROVED'::application_status THEN
        RAISE EXCEPTION 'Cannot modify approved application'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Approved applications are immutable for audit purposes';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION prevent_approved_application_modification() IS
    'Prevents modification of approved applications (audit trail protection).';

/**
 * FUNCTION: set_reviewed_at_timestamp()
 * Purpose: Automatically set reviewed_at when status changes from NEW
 * Trigger: BEFORE UPDATE ON expert_applications
 */
CREATE OR REPLACE FUNCTION set_reviewed_at_timestamp()
    RETURNS TRIGGER AS $$
BEGIN
    -- Set reviewed_at when moving from NEW to any other status
    IF OLD.status = 'NEW'::application_status AND
       NEW.status != 'NEW'::application_status AND
       NEW.reviewed_at IS NULL THEN
        NEW.reviewed_at := CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_reviewed_at_timestamp() IS
    'Automatically sets reviewed_at timestamp when application review begins.';

/**
 * FUNCTION: validate_expert_rating_update()
 * Purpose: Ensure rating changes are consistent with review count
 * Trigger: BEFORE UPDATE ON expert_profiles
 */
CREATE OR REPLACE FUNCTION validate_expert_rating_update()
    RETURNS TRIGGER AS $$
BEGIN
    -- If review count is 0, rating must be 0.00
    IF NEW.review_count = 0 AND NEW.rating != 0.00 THEN
        RAISE EXCEPTION 'Rating must be 0.00 when review_count is 0'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Cannot have rating without reviews';
    END IF;

    -- If review count > 0, rating must be > 0.00
    IF NEW.review_count > 0 AND NEW.rating = 0.00 THEN
        RAISE EXCEPTION 'Rating must be greater than 0.00 when reviews exist'
            USING ERRCODE = 'integrity_constraint_violation',
                HINT = 'Rating should reflect existing reviews';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_expert_rating_update() IS
    'Validates consistency between rating and review_count fields.';

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

-- Expert applications workflow
CREATE TRIGGER expert_applications_create_profile_on_approval
    AFTER UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION create_expert_profile_on_approval();

CREATE TRIGGER expert_applications_prevent_approved_modification
    BEFORE UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION prevent_approved_application_modification();

CREATE TRIGGER expert_applications_set_reviewed_at
    BEFORE UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION set_reviewed_at_timestamp();

CREATE TRIGGER expert_applications_update_updated_at
    BEFORE UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Expert profiles validation
CREATE TRIGGER expert_profiles_validate_rating
    BEFORE UPDATE ON expert_profiles
    FOR EACH ROW EXECUTE FUNCTION validate_expert_rating_update();

CREATE TRIGGER expert_profiles_update_updated_at
    BEFORE UPDATE ON expert_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- GRANTS: Role-based access control
-- ============================================================================
-- GRANT SELECT, INSERT ON expert_applications TO app_user;
-- GRANT UPDATE ON expert_applications TO app_admin; -- Only admins approve
-- GRANT SELECT ON expert_profiles TO app_user;
-- GRANT UPDATE ON expert_profiles TO app_user; -- Experts update their own
-- GRANT SELECT ON expert_profiles TO app_readonly;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================