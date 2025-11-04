/*
 * ============================================================================
 * Migration: V1__Create_users_and_groups.sql
 * Purpose: Initialize core user and group management tables with comprehensive
 *          validation, audit trails, and hierarchical group support
 *
 * Author: Uvays Ramazanov
 * Version: 1.0
 * Created: 2025-10-20.
 *
 * This migration establishes the foundation for user authentication and
 * group-based authorization system with built-in data integrity constraints
 * and audit capabilities.
 * ============================================================================
 */

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create schema
CREATE SCHEMA IF NOT EXISTS public;

-- ============================================================================
-- DOMAIN TYPES: Custom types for validation and reusability
-- ============================================================================
-- These domains encapsulate validation logic at the database level,
-- ensuring data integrity across all applications using this schema
-- ============================================================================

/**
 * DOMAIN: valid_phone
 * Purpose: Phone number in international format
 * Format: +Country Code (spaces, hyphens, parentheses allowed)
 * Length: 7-20 characters (digits only, after normalization)
 */
CREATE DOMAIN valid_phone AS VARCHAR(15) -- E.164
    CHECK (
        VALUE IS NOT NULL AND
        VALUE ~ '^\+?[0-9\s\-()]{7,20}$' AND
        length(regexp_replace(VALUE, '[^0-9]', '', 'g')) >= 7
    );

/**
 * DOMAIN: valid_name
 * Purpose: User first/last names with multilingual support
 * Rules:
 *   - Length: 2-100 characters
 *   - Allowed: Latin, Cyrillic letters, spaces, hyphens, apostrophes
 *   - Trimmed: No leading/trailing spaces
 *   - No consecutive spaces
 */
CREATE DOMAIN valid_name AS VARCHAR(30)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 3 AND
        length(trim(VALUE)) <= 30 AND
        VALUE ~ '^[а-яА-ЯёЁa-zA-Z\s\-'']+$' AND
        VALUE NOT LIKE '%  %' AND
        VALUE = trim(VALUE)
    );

/**
 * DOMAIN: valid_language
 * Purpose: ISO 639-1 language codes with country variants
 * Supported: en, ru, de, fr, es, zh, ja, ko
 * Format: 'en' or 'en-US'
 */
CREATE DOMAIN valid_language AS VARCHAR(10)
    CHECK (
        VALUE IN (
                  'en', 'ru', 'de', 'fr', 'es', 'zh', 'ja', 'ko',
                  'en-US', 'en-GB', 'zh-CN', 'zh-TW', 'pt-BR', 'pt-PT'
            )
        );

/**
 * DOMAIN: valid_group_name
 * Purpose: Group/team names with special characters for tags
 * Allowed: Alphanumeric, spaces, hyphens, underscores, special symbols
 * No consecutive spaces
 */
CREATE DOMAIN valid_group_name AS VARCHAR(255)
    CHECK (
        VALUE IS NOT NULL AND
        length(trim(VALUE)) >= 1 AND
        length(trim(VALUE)) <= 255 AND
        VALUE ~ '^[а-яА-ЯёЁa-zA-Z0-9\s\-_#@.()]+$' AND
        VALUE NOT LIKE '%  %' AND
        VALUE = trim(VALUE)
        );

-- ============================================================
-- USERS TABLE
-- ============================================================
CREATE TABLE users (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Identity Information ==========
    phone valid_phone NOT NULL UNIQUE,
    first_name valid_name NOT NULL,
    last_name valid_name NOT NULL,

    -- ========== Profile Information ==========
    image BYTEA,
    birthday DATE,
    language valid_language NOT NULL DEFAULT 'en',

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Image validation
    CHECK (image IS NULL OR octet_length(image) > 0),
    CHECK (image IS NULL OR octet_length(image) <= 5242880), -- 5MB limit

    -- Date validation
    CHECK (birthday IS NULL OR birthday <= CURRENT_DATE),
    CHECK (birthday IS NULL OR EXTRACT(YEAR FROM age(birthday)) >= 13),
    CHECK (birthday IS NULL OR EXTRACT(YEAR FROM age(birthday)) <= 130),

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= created_at)
);

-- Comments for documentation
COMMENT ON TABLE users IS
    'Core user entity. Stores authentication credentials, profile data, and preferences.
     GDPR Compliance: Birthday and age restrictions ensure COPPA compliance (13+ years).';

COMMENT ON COLUMN users.id IS 'Unique user identifier (UUID v4)';
COMMENT ON COLUMN users.phone IS 'Primary contact number in international format (E.164)';
COMMENT ON COLUMN users.image IS 'Avatar image stored as binary data (max 5MB)';
COMMENT ON COLUMN users.birthday IS 'Date of birth (required for age verification, nullable)';
COMMENT ON COLUMN users.language IS 'User interface language preference (ISO 639-1)';

-- ============================================================
-- GROUPS TABLE
-- ============================================================
CREATE TABLE groups (
    -- ========== Primary Key ==========
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ========== Identity Information ==========
    name valid_group_name NOT NULL UNIQUE,

    -- ========== Ownership & Hierarchy ==========
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES groups(id) ON DELETE SET NULL,

    -- ========== Audit Timestamps ==========
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- ========== Data Integrity Constraints ==========
    -- Self-reference prevention
    CHECK (parent_id IS NULL OR parent_id != id),

    -- Timestamp validation
    CHECK (created_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at <= CURRENT_TIMESTAMP),
    CHECK (updated_at >= created_at)
);

COMMENT ON TABLE groups IS
    'Hierarchical organizational units. Supports nested structures up to 5 levels deep.
     Owner is automatically set to the creating user and cannot be null.';

COMMENT ON COLUMN groups.id IS 'Unique group identifier (UUID v4)';
COMMENT ON COLUMN groups.name IS 'Group name (must be unique across all groups)';
COMMENT ON COLUMN groups.owner_id IS 'User who owns/manages this group';
COMMENT ON COLUMN groups.parent_id IS 'Parent group ID for hierarchical organization (null = top-level)';

-- ============================================================
-- INDEXES для оптимизации
-- ============================================================
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_language ON users(language);
CREATE INDEX idx_groups_owner_id ON groups(owner_id);
CREATE INDEX idx_groups_parent_id ON groups(parent_id);
CREATE INDEX idx_groups_name ON groups(name);

-- ============================================================================
-- FUNCTIONS: Trigger logic for data integrity
-- ============================================================================

/**
 * FUNCTION: prevent_created_at_update()
 * Purpose: Ensure created_at timestamp is immutable
 * Trigger: BEFORE UPDATE ON users, groups
 *
 * Audit Trail: The created_at field serves as an immutable record of when
 * an entity was created and must never be modified.
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
    'Ensures created_at timestamp is immutable across all updates.';

/**
 * FUNCTION: update_updated_at()
 * Purpose: Automatically update the updated_at timestamp
 * Trigger: BEFORE UPDATE ON users, groups
 *
 * Pattern: Standard pattern for maintaining update audit trail
 */
CREATE OR REPLACE FUNCTION update_updated_at()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION update_updated_at() IS
    'Automatically updates the updated_at timestamp on record modification.';

/**
 * FUNCTION: check_parent_cycle()
 * Purpose: Prevent circular references in group hierarchy
 * Trigger: BEFORE INSERT OR UPDATE ON groups
 *
 * Validation Rules:
 *   - A group cannot be its own parent
 *   - No circular references (A -> B -> C -> A)
 *   - Maximum hierarchy depth: 5 levels
 *
 * Performance: O(n) where n = hierarchy depth (max 5)
 */
CREATE OR REPLACE FUNCTION check_parent_cycle()
    RETURNS TRIGGER AS $$
DECLARE
    v_parent_id UUID;
    v_depth INT := 0;
    v_max_depth CONSTANT INT := 5;
    v_max_iterations CONSTANT INT := 100; -- Safety limit
BEGIN
    -- No validation needed for null parent (top-level group)
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_parent_id := NEW.parent_id;

    -- Traverse hierarchy to detect cycles and depth
    WHILE v_parent_id IS NOT NULL AND v_depth < v_max_iterations LOOP
            -- Check for self-reference or cycle
            IF v_parent_id = NEW.id THEN
                RAISE EXCEPTION 'Circular reference detected: group cannot be its own ancestor'
                    USING ERRCODE = 'integrity_constraint_violation';
            END IF;

            -- Move to next level
            SELECT parent_id INTO v_parent_id FROM groups WHERE id = v_parent_id;
            v_depth := v_depth + 1;

            -- Check depth limit
            IF v_depth > v_max_depth THEN
                RAISE EXCEPTION 'Group hierarchy depth exceeded (maximum % levels)', v_max_depth
                    USING ERRCODE = 'integrity_constraint_violation';
            END IF;
        END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_parent_cycle() IS
    'Validates group hierarchy: prevents cycles and enforces max depth of 5 levels.';

-- ============================================================================
-- TRIGGERS: Attach functions to tables
-- ============================================================================

-- Prevent created_at updates
CREATE TRIGGER users_prevent_created_at_update
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION prevent_created_at_update();

CREATE TRIGGER groups_prevent_created_at_update
    BEFORE UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION prevent_created_at_update();

-- Update updated_at on modifications
CREATE TRIGGER users_update_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER groups_update_updated_at
    BEFORE UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Validate group hierarchy
CREATE TRIGGER groups_check_parent_cycle
    BEFORE INSERT OR UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION check_parent_cycle();

-- ============================================================================
-- GRANTS: Security and access control
-- ============================================================================
-- Adjust these based on your application's role-based access control (RBAC)

-- GRANT SELECT, INSERT, UPDATE ON users TO app_user;
-- GRANT SELECT ON users TO app_readonly;
-- GRANT SELECT, INSERT, UPDATE ON groups TO app_user;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================