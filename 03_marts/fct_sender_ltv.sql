-- =============================================================================
-- fct_sender_ltv
-- =============================================================================
-- METRIC: Sender LTV (Lifetime Value)
--
-- Two complementary calculations are provided. Stakeholders pick based
-- on the decision at hand.
--
--   1. gmv_lifetime_usd
--      Cumulative GMV from accepted gifts per sender, all-time.
--      Pros: simple, intuitive, matches Finance / CS reporting.
--      Cons: NOT comparable across cohorts — a sender active for 12
--            months mechanically looks "better" than one active for 3,
--            independent of true value.
--      Use for: Sales / CS account prioritization, Finance reporting.
--
--   2. gmv_first_180d_usd
--      GMV accepted within 180 days of the sender's FIRST gift sent.
--      Senders with < 180 days of tenure are excluded (NULL) — insufficient
--      maturation to compare fairly.
--      Pros: cohort-comparable. Senders acquired in different periods can
--            be benchmarked. Detects whether onboarding changes shift LTV.
--      Cons: ignores long-tail revenue from highly engaged power users.
--      Use for: Growth experiments, onboarding A/B tests, channel ROI.
--
-- Why "first activity" = MIN(batch_created_at) instead of users.created_at:
--   users.created_at has data quality issues — 28 users (~11%) have a
--   user_created_at AFTER their first sent batch, which is impossible
--   if user_created_at were a true signup timestamp. We treat the first
--   batch as a more reliable activity anchor. See stg_users.sql.
--
-- Edge cases handled:
--   - Senders with zero accepted gifts: INCLUDED with $0 LTV (not dropped).
--     Useful for activation analysis ("which senders never converted?").
--   - Lifecycle anomalies: NOT excluded here because we want to count
--     the sender's revenue accurately. Their 12-row footprint is
--     negligible at the sender grain.
--
-- Grain: one row per sender_user_id
--
-- Usage:
--   - Median LTV is more informative than mean (right-skewed).
--   - ALWAYS segment by sender_segment when comparing across cohorts.
--   - For acquisition channels: filter to senders whose first_active_at
--     falls in the channel's launch window.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.fct_sender_ltv` AS

WITH sender_first_activity AS (
    -- First batch_created_at per sender — our proxy for activation date
    SELECT
        sender_user_id,
        MIN(batch_created_at) AS first_active_at
    FROM `goody_analytics.stg_gift_batches`
    GROUP BY 1
),

sender_facts AS (
    SELECT
        g.sender_user_id,
        ANY_VALUE(g.company_id)   AS company_id,
        ANY_VALUE(g.plan_type)    AS plan_type,
        ANY_VALUE(g.industry)     AS industry,

        COUNT(*)                                          AS gifts_sent,
        COUNTIF(g.was_accepted)                           AS gifts_accepted,
        SUM(IF(g.was_accepted, g.final_amount_cents, 0))  AS gmv_lifetime_cents,

        MIN(g.sent_at)                                    AS first_sent_at,
        MAX(g.sent_at)                                    AS last_sent_at

    FROM `goody_analytics.int_gifts_enriched` g
    GROUP BY 1
),

sender_first_180d AS (
    -- GMV in first 180 days after sender's first activity
    SELECT
        g.sender_user_id,
        SUM(IF(g.was_accepted, g.final_amount_cents, 0)) AS gmv_first_180d_cents
    FROM      `goody_analytics.int_gifts_enriched` g
    JOIN      sender_first_activity                fa USING (sender_user_id)
    WHERE g.sent_at < TIMESTAMP_ADD(fa.first_active_at, INTERVAL 180 DAY)
    GROUP BY 1
)

SELECT
    sf.sender_user_id,
    sf.company_id,
    sf.plan_type,
    sf.industry,
    seg.sender_segment,

    fa.first_active_at,
    sf.first_sent_at,
    sf.last_sent_at,
    TIMESTAMP_DIFF(sf.last_sent_at, sf.first_sent_at, DAY) AS sender_tenure_days,

    sf.gifts_sent,
    sf.gifts_accepted,
    ROUND(SAFE_DIVIDE(sf.gifts_accepted, sf.gifts_sent), 4) AS acceptance_rate,

    -- LTV v1: cumulative lifetime
    ROUND(sf.gmv_lifetime_cents / 100.0, 2) AS gmv_lifetime_usd,

    -- LTV v2: first-180-days cohort (NULL if sender < 180 days tenure)
    CASE
        WHEN DATE_ADD(DATE(fa.first_active_at), INTERVAL 180 DAY) <= CURRENT_DATE()
        THEN ROUND(s180.gmv_first_180d_cents / 100.0, 2)
        ELSE NULL
    END AS gmv_first_180d_usd

FROM      sender_facts                              sf
LEFT JOIN sender_first_activity                     fa   USING (sender_user_id)
LEFT JOIN sender_first_180d                         s180 USING (sender_user_id)
LEFT JOIN `goody_analytics.int_sender_segment`      seg  USING (company_id)
;
