-- =============================================================================
-- stg_gift_batches
-- =============================================================================
-- Purpose: Clean and type-cast batches.
-- Grain:   one row per batch_id
-- Notes:
--   - 2,590 distinct batches in source
--   - scheduled_send_at is NULL for batches sent immediately (~81%);
--     for the remaining ~19% the actual sent_at on each gift is within
--     a few days of batch_created_at, so we trust gift.sent_at as the
--     authoritative "when did it actually go out" timestamp.
--   - gift_type values: specific_gift, gift_of_choice, collection
--   - is_international is at batch level (an entire batch is or isn't
--     international — never mixed within a batch).
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.stg_gift_batches` AS

SELECT
    batch_id,
    sender_user_id,
    SAFE_CAST(created_at AS TIMESTAMP)        AS batch_created_at,
    SAFE_CAST(scheduled_send_at AS TIMESTAMP) AS scheduled_send_at,
    LOWER(gift_type)                          AS gift_type,
    SAFE_CAST(is_international AS BOOL)       AS is_international
FROM `goody_raw.gift_batches`
;
