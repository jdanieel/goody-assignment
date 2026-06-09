-- =============================================================================
-- int_sender_segment
-- =============================================================================
-- Purpose: Classify each company as 'mass_outreach' or 'targeted' based on
--          observed behavior — NOT hardcoded names. This makes the
--          classification scale automatically as new companies onboard
--          and is auditable from the rules below.
--
-- Why this matters:
--   Three companies in the data send ~71% of all gifts but generate only
--   ~24% of GMV, with acceptance rates near 10%. Their pattern (bulk
--   email-blast style sending) is operationally and economically distinct
--   from "relational" corporate gifting. Without separating them, every
--   aggregate metric is dominated by their behavior.
--
-- Definition (v1):
--   A company is 'mass_outreach' if it has >= 100 total gifts sent
--   AND EITHER of:
--     (a) median gifts-per-batch >= 50, OR
--     (b) matured acceptance rate <= 20%
--
--   Companies with < 100 total gifts default to 'targeted' (insufficient
--   signal; conservative choice).
--
-- Justification of thresholds:
--   - Batch size: among observed targeted companies, p90 batch size is ~50.
--     A median >= 50 means HALF the batches are above that p90 — clearly
--     bulk behavior.
--   - Acceptance rate: targeted companies average 74% acceptance. 20% is
--     well below the lowest observed targeted-company rate, leaving a
--     safe buffer.
--   - Min volume of 100: protects against noise; the lowest-volume
--     observed company sent ~50 gifts, so 100 excludes essentially no
--     real senders.
--
-- Grain:   one row per company_id
-- Notes:
--   - Acceptance rate uses ONLY matured gifts (sent_at <= CURRENT_DATE - 14)
--     to avoid penalizing recent activity that hasn't had time to accept.
--     See fct_acceptance_rate.sql for the maturation rationale.
--   - This is a v1. Future iterations could add: trend (is the company
--     drifting toward bulk?), seasonality adjustment, batch-size variance.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.int_sender_segment` AS

WITH company_batches AS (
    -- Gifts per batch, per company (one row per batch)
    SELECT
        g.company_id,
        g.batch_id,
        COUNT(*) AS gifts_in_batch
    FROM `goody_analytics.int_gifts_enriched` g
    GROUP BY 1, 2
),

batch_size_stats AS (
    SELECT
        company_id,
        APPROX_QUANTILES(gifts_in_batch, 100)[OFFSET(50)] AS median_gifts_per_batch
    FROM company_batches
    GROUP BY 1
),

company_stats AS (
    SELECT
        g.company_id,
        COUNT(*)                                        AS total_gifts_sent,
        COUNTIF(g.was_accepted)                         AS total_gifts_accepted,

        -- Matured: only gifts that have had >=14 days to accept
        COUNTIF(
            DATE(g.sent_at) <= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
            AND NOT g.has_lifecycle_anomaly
        ) AS matured_gifts_sent,
        COUNTIF(
            DATE(g.sent_at) <= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
            AND NOT g.has_lifecycle_anomaly
            AND g.was_accepted
        ) AS matured_gifts_accepted

    FROM `goody_analytics.int_gifts_enriched` g
    GROUP BY 1
),

joined AS (
    SELECT
        cs.company_id,
        cs.total_gifts_sent,
        cs.matured_gifts_sent,
        cs.matured_gifts_accepted,
        SAFE_DIVIDE(cs.matured_gifts_accepted, cs.matured_gifts_sent) AS acceptance_rate,
        bss.median_gifts_per_batch
    FROM company_stats cs
    LEFT JOIN batch_size_stats bss USING (company_id)
)

SELECT
    j.company_id,
    j.total_gifts_sent,
    j.median_gifts_per_batch,
    ROUND(j.acceptance_rate, 4) AS acceptance_rate,

    CASE
        -- Insufficient volume: default to targeted (conservative)
        WHEN j.total_gifts_sent < 100 THEN 'targeted'

        -- Mass-outreach pattern: bulk batches OR very low acceptance
        WHEN j.median_gifts_per_batch >= 50 THEN 'mass_outreach'
        WHEN j.acceptance_rate <= 0.20      THEN 'mass_outreach'

        ELSE 'targeted'
    END AS sender_segment

FROM joined j
;
