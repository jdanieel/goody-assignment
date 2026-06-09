-- =============================================================================
-- int_gifts_enriched
-- =============================================================================
-- Purpose: One row per gift joined with batch + sender + company + product
--          context. This is the workhorse table — most downstream queries
--          and ad-hoc analyses should hit this and avoid re-joining the
--          staging layer.
--
-- Grain:   one row per gift_id
--
-- Notes:
--   - All joins are LEFT JOINs anchored on stg_gifts to preserve every
--     gift, even if reference data is missing (it isn't in this dataset,
--     but defensive practice).
--   - has_lifecycle_anomaly flag is carried through; marts decide whether
--     to exclude.
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.int_gifts_enriched` AS

SELECT
    -- gift facts
    g.gift_id,
    g.batch_id,
    g.product_id,
    g.recipient_email,
    g.sent_at,
    g.opened_at,
    g.accepted_at,
    g.shipped_at,
    g.delivered_at,
    g.final_amount_cents,
    g.was_swapped,
    g.was_opened,
    g.was_accepted,
    g.was_shipped,
    g.was_delivered,
    g.days_to_accept,
    g.has_lifecycle_anomaly,
    g.is_lifecycle_censored,

    -- batch facts
    b.sender_user_id,
    b.batch_created_at,
    b.scheduled_send_at,
    (b.scheduled_send_at IS NOT NULL) AS was_scheduled,
    b.gift_type,
    b.is_international,

    -- sender / company facts
    u.user_created_at,
    c.company_id,
    c.company_name,
    c.industry,
    c.plan_type,
    c.employee_count,
    c.company_created_at,

    -- product facts
    p.brand_name,
    p.category,
    p.list_price_cents,
    p.is_swag

FROM      `goody_analytics.stg_gifts`         g
LEFT JOIN `goody_analytics.stg_gift_batches`  b USING (batch_id)
LEFT JOIN `goody_analytics.stg_users`         u ON b.sender_user_id = u.user_id
LEFT JOIN `goody_analytics.stg_companies`     c ON u.company_id = c.company_id
LEFT JOIN `goody_analytics.stg_products`      p USING (product_id)
;
