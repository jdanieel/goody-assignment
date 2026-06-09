-- =============================================================================
-- fct_acceptance_rate
-- =============================================================================
-- METRIC: Gift Acceptance Rate
--
-- Definition:
--   Numerator:   gifts where accepted_at IS NOT NULL
--   Denominator: gifts where sent_at <= CURRENT_DATE - 14 days
--                (gifts that have had at least 14 days to be accepted)
--
-- Why a 14-day maturation window:
--   Distribution of days-to-accept among accepted gifts in the historical
--   data:
--       within  1 day:   2.5%
--       within  3 days: 21.9%
--       within  7 days: 78.7%
--       within 14 days: 100.0%
--   A shorter window understates acceptance for recent cohorts (they
--   look artificially low). A longer window throws data away without
--   capturing additional acceptances.
--
-- Edge cases handled:
--   - Gifts sent within the last 14 days: EXCLUDED from both numerator
--     and denominator. Tracking them in a separate "pipeline" view is a
--     good follow-up but kept out of this metric to keep the definition
--     clean.
--   - Lifecycle anomalies (12 rows): EXCLUDED.
--   - Censored rows: KEPT. This metric is anchored on sent_at (always
--     real) and acceptance is a boolean — so censoring of accepted_at
--     does not affect this calculation. Verified empirically: including
--     vs excluding censored rows produces identical acceptance rates.
--   - was_swapped is irrelevant to acceptance (swap happens after).
--
-- Anchor: sent_at (cohort metric: "of gifts sent on day X, what fraction
--   were eventually accepted?"). Do NOT anchor on accepted_at — that
--   would give "of gifts accepted on day X, what fraction were accepted?"
--   which is always 100%.
--
-- Grain: one row per
--   (sent_date, sender_segment, gift_type, is_international,
--    plan_type, industry)
--
-- Usage:
--   - Mass vs targeted acceptance rates are wildly different
--     (~10% vs ~74%). ALWAYS segment when reporting.
--   - For monitoring: aggregate to (sent_date, sender_segment) and watch
--     for shifts > 5pp from rolling 4-week baseline.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.fct_acceptance_rate` AS

SELECT
    DATE(g.sent_at)             AS sent_date,
    seg.sender_segment,
    g.gift_type,
    g.is_international,
    g.plan_type,
    g.industry,

    COUNT(*)                                              AS gifts_sent,
    COUNTIF(g.was_accepted)                               AS gifts_accepted,
    ROUND(SAFE_DIVIDE(COUNTIF(g.was_accepted), COUNT(*)), 4) AS acceptance_rate

FROM      `goody_analytics.int_gifts_enriched` g
LEFT JOIN `goody_analytics.int_sender_segment` seg USING (company_id)
WHERE DATE(g.sent_at) <= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  AND NOT g.has_lifecycle_anomaly
GROUP BY 1, 2, 3, 4, 5, 6
;
