-- =============================================================================
-- stg_products
-- =============================================================================
-- Purpose: Clean and type-cast products.
-- Grain:   one row per product_id
-- Notes:
--   - 134 distinct products / 8 categories
--   - Renamed price_cents -> list_price_cents to disambiguate from
--     gifts.final_amount_cents (the actual charged amount, which can
--     differ when was_swapped = TRUE).
--   - is_swag = TRUE for customizable branded products
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.stg_products` AS

SELECT
    product_id,
    brand_name,
    LOWER(category)                 AS category,
    SAFE_CAST(price_cents AS INT64) AS list_price_cents,
    SAFE_CAST(is_swag AS BOOL)      AS is_swag
FROM `goody_raw.products`
;
