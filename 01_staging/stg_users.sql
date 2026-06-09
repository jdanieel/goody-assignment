-- =============================================================================
-- stg_users
-- =============================================================================
-- Purpose: Clean and type-cast users.
-- Grain:   one row per user_id
-- Notes:
--   - 252 distinct users across 47 companies
--   - DATA QUALITY: 28 users (~11%) have user_created_at AFTER their first
--     sent batch. This means users.created_at is NOT a reliable signup date.
--     Downstream models should use MIN(batch_created_at) per sender_user_id
--     as the proxy for first activity — see fct_sender_ltv.sql.
--   - 99% of users have sent at least one batch (only 2 are pure-recipient
--     no-send accounts), so this dataset gives almost no signal for
--     activation-funnel analysis.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.stg_users` AS

SELECT
    user_id,
    SAFE_CAST(created_at AS TIMESTAMP) AS user_created_at,
    company_id
FROM `goody_raw.users`
;
