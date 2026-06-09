-- =============================================================================
-- fct_gmv_daily
-- =============================================================================
-- METRIC: GMV (Gross Merchandise Value)
--
-- Definition:
--   GMV = SUM(final_amount_cents) for gifts where accepted_at IS NOT NULL
--   Recognized on the date of accepted_at.
--
-- Why accepted_at (and not sent_at or batch.created_at):
--   The business rule is "Goody charges the sender at acceptance, and
--   recognizes revenue at that point" (see briefing). So GMV is realized
--   on accepted_at. Anchoring on sent_at would shift revenue into the
--   wrong period; anchoring on batch.created_at would shift even further
--   (batches can include scheduled future sends).
--
-- Edge cases handled:
--   - Non-accepted gifts: excluded (final_amount_cents is 0 for them
--     anyway, so they would contribute nothing — but the WHERE makes
--     the intent explicit).
--   - Lifecycle anomalies (12 rows): excluded.
--   - Censored rows (~584 with accepted_at = sentinel): KEPT. Their GMV
--     is real; only the timestamp is truncated to snapshot moment.
--   - Swapped gifts (was_swapped = TRUE): INCLUDED. final_amount_cents
--     reflects the actually-charged amount post-swap.
--   - Scheduled future batches with no acceptance yet: naturally excluded
--     (no accepted_at).
--
-- KNOWN DISTORTION:
--   The date 2025-12-31 carries ~$51k in censored GMV (~3% of annual,
--   ~10x the typical daily total). Any consumer cutting GMV at daily/weekly
--   grain near year-end should either:
--     (a) join back to int_gifts_enriched and filter is_lifecycle_censored,
--     (b) aggregate to monthly grain (distortion absorbed), or
--     (c) annotate the chart explicitly.
--   For pacing/trend analysis, consider sending-date views as well (see
--   fct_acceptance_rate, which is anchored on sent_at and unaffected by
--   the snapshot censoring).
--
-- Currency: USD assumed (only one currency in the dataset).
--
-- Grain: one row per
--   (accepted_date, sender_segment, plan_type, industry,
--    is_international, is_swag, gift_type)
--
-- Usage:
--   - For exec dashboards: aggregate up to (accepted_date, sender_segment).
--   - For Growth segmentation: filter to sender_segment = 'targeted'.
--   - For category mix: join back to int_gifts_enriched if needed.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.fct_gmv_daily` AS

SELECT
    DATE(g.accepted_at)                         AS accepted_date,
    seg.sender_segment,
    g.plan_type,
    g.industry,
    g.is_international,
    g.is_swag,
    g.gift_type,

    COUNT(*)                                    AS gifts_accepted,
    COUNTIF(g.was_swapped)                      AS gifts_swapped,
    SUM(g.final_amount_cents)                   AS gmv_cents,
    ROUND(SUM(g.final_amount_cents) / 100.0, 2) AS gmv_usd,
    ROUND(AVG(g.final_amount_cents) / 100.0, 2) AS avg_amount_usd

FROM      `goody_analytics.int_gifts_enriched` g
LEFT JOIN `goody_analytics.int_sender_segment` seg USING (company_id)
WHERE g.was_accepted
  AND NOT g.has_lifecycle_anomaly
GROUP BY 1, 2, 3, 4, 5, 6, 7
;
