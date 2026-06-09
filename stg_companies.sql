-- =============================================================================
-- stg_companies
-- =============================================================================
-- Purpose: Clean and type-cast companies from raw CSV import.
-- Grain:   one row per company_id
-- Notes:
--   - 47 distinct companies in source
--   - plan_type values observed: starter, pro, team (no nulls)
--   - industry values: technology, financial_services, healthcare, retail,
--     professional_services, manufacturing, education, media
-- =============================================================================

CREATE OR REPLACE TABLE `goody_analytics.stg_companies` AS

SELECT
    company_id,
    name                                AS company_name,
    SAFE_CAST(employee_count AS INT64)  AS employee_count,
    LOWER(industry)                     AS industry,
    SAFE_CAST(created_at AS TIMESTAMP)  AS company_created_at,
    LOWER(plan_type)                    AS plan_type
FROM `goody_raw.companies`
;
