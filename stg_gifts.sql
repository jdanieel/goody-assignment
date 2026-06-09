-- =============================================================================
-- stg_gifts
-- =============================================================================
-- Purpose: Clean, type-cast, and flag gift-level lifecycle events.
-- Grain:   one row per gift_id (66,956 rows in source)
-- Notes:
--
--   Lifecycle null pattern (% of all gifts):
--     sent_at:       100.0%  (always populated)
--     opened_at:      44.0%
--     accepted_at:    28.7%
--     shipped_at:     28.6%
--     delivered_at:   28.3%
--
--   Confirmed: final_amount_cents == 0 for ALL non-accepted gifts and > 0
--   for ALL accepted gifts. So GMV filter on accepted_at IS NOT NULL is
--   equivalent to filtering on final_amount_cents > 0 (we use the former
--   for clarity).
--
--   TWO KINDS OF DATA-QUALITY ISSUES handled with separate flags:
--
--   (A) has_lifecycle_anomaly — 12 rows with LOGICALLY IMPOSSIBLE orderings:
--         - 11 gifts: accepted_at < opened_at (impossible)
--         -  1 gift: accepted_at populated but opened_at NULL
--       These rows are excluded from the GMV and acceptance-rate marts.
--
--   (B) is_lifecycle_censored — rows where one or more lifecycle timestamps
--       equal the snapshot-cutoff sentinel '2025-12-31 23:59:59':
--         -    92 gifts with opened_at    = sentinel
--         -   584 gifts with accepted_at  = sentinel
--         -   823 gifts with shipped_at   = sentinel
--         - 1,336 gifts with delivered_at = sentinel
--       Interpretation: the dataset was snapshotted at 2025-12-31 23:59:59
--       and gifts whose lifecycle hadn't completed yet had their pending
--       timestamps set to the snapshot moment. This is RIGHT-CENSORING,
--       not anomaly — the underlying acceptance/GMV is real, only the
--       exact "when" is imprecise.
--       These rows are KEPT in all marts (their final_amount_cents is
--       populated and reflects real GMV). Consumers should be aware that
--       any GMV cut at the date 2025-12-31 will be artificially inflated
--       (~$51k concentrated on that single date out of $1.71M annual GMV).
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.stg_gifts` AS

SELECT
    gift_id,
    batch_id,
    product_id,
    recipient_email,

    SAFE_CAST(sent_at      AS TIMESTAMP) AS sent_at,
    SAFE_CAST(opened_at    AS TIMESTAMP) AS opened_at,
    SAFE_CAST(accepted_at  AS TIMESTAMP) AS accepted_at,
    SAFE_CAST(shipped_at   AS TIMESTAMP) AS shipped_at,
    SAFE_CAST(delivered_at AS TIMESTAMP) AS delivered_at,

    SAFE_CAST(final_amount_cents AS INT64) AS final_amount_cents,
    SAFE_CAST(was_swapped AS BOOL)         AS was_swapped,

    -- Lifecycle boolean flags
    sent_at      IS NOT NULL AS was_sent,
    opened_at    IS NOT NULL AS was_opened,
    accepted_at  IS NOT NULL AS was_accepted,
    shipped_at   IS NOT NULL AS was_shipped,
    delivered_at IS NOT NULL AS was_delivered,

    -- Days from sent to accept (NULL if not accepted)
    CASE
        WHEN accepted_at IS NOT NULL
        THEN TIMESTAMP_DIFF(accepted_at, sent_at, DAY)
    END AS days_to_accept,

    -- Anomaly flag: logically impossible orderings (12 rows).
    -- Marts EXCLUDE these.
    CASE
        WHEN accepted_at IS NOT NULL
         AND (opened_at IS NULL OR accepted_at < opened_at)
        THEN TRUE
        ELSE FALSE
    END AS has_lifecycle_anomaly,

    -- Censoring flag: lifecycle timestamps truncated to snapshot moment.
    -- Marts KEEP these (real GMV, only timestamps imprecise).
    -- Consumers should be aware of date-level concentration on 2025-12-31.
    CASE
        WHEN opened_at    = TIMESTAMP '2025-12-31 23:59:59' THEN TRUE
        WHEN accepted_at  = TIMESTAMP '2025-12-31 23:59:59' THEN TRUE
        WHEN shipped_at   = TIMESTAMP '2025-12-31 23:59:59' THEN TRUE
        WHEN delivered_at = TIMESTAMP '2025-12-31 23:59:59' THEN TRUE
        ELSE FALSE
    END AS is_lifecycle_censored

FROM `goody_raw.gifts`
;
