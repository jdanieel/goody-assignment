# Goody Data Analyst — Take Home Assignment (SQL)

## Setup

**SQL dialect:** BigQuery (Standard SQL)
**Tested in:** BigQuery Sandbox (free tier, no billing required)

### Prerequisites

Two datasets in your BigQuery project:

- `goody_raw` — contains the 5 source CSVs loaded as tables: `companies`, `users`, `gift_batches`, `gifts`, `products`
- `goody_analytics` — empty; this is where the models will be created

If your dataset names differ, do a project-wide find-and-replace on `goody_raw` and `goody_analytics`.

### How to run

In the BigQuery console, run the files in this order. Each file is independent within its layer — staging files can run in any order, but layers must be run in sequence:

```
1. 01_staging/stg_companies.sql
   01_staging/stg_users.sql
   01_staging/stg_gift_batches.sql
   01_staging/stg_gifts.sql
   01_staging/stg_products.sql

2. 02_intermediate/int_gifts_enriched.sql       (must run before int_sender_segment)
   02_intermediate/int_sender_segment.sql

3. 03_marts/fct_gmv_daily.sql
   03_marts/fct_acceptance_rate.sql
   03_marts/fct_sender_ltv.sql
```

Total runtime: under a minute on this volume (~67k gifts).

---

## Project structure

```
01_staging/        Clean, type-cast, flag anomalies. No business logic.
02_intermediate/   Joins and behavioral classification.
03_marts/          Final, consumption-ready metric tables.
```

This mirrors a dbt-style staging → intermediate → marts pattern. Each model has a header comment describing purpose, grain, and edge-case decisions.

---

## Metric definitions (the three required metrics)

### 1. GMV — `fct_gmv_daily`

**Definition:** Sum of `final_amount_cents` from gifts where `accepted_at IS NOT NULL`, recognized on the date of `accepted_at`.

**Why `accepted_at` and not `sent_at`:** The business rule from the briefing is that Goody charges the sender at acceptance. Recognizing revenue on `sent_at` would shift it into the wrong period; recognizing on `batch.created_at` would shift it even further.

**Edge cases:**
- Non-accepted gifts excluded (`final_amount_cents = 0` for all of them anyway).
- 12 rows with lifecycle anomalies excluded.
- Swapped gifts included — `final_amount_cents` reflects the actually-charged amount after the swap.
- Currency: USD assumed (only one currency in the data).

### 2. Gift Acceptance Rate — `fct_acceptance_rate`

**Definition:**
- Numerator: gifts where `accepted_at IS NOT NULL`
- Denominator: gifts where `sent_at <= CURRENT_DATE - 14 days`

**Why a 14-day maturation window:** Empirical distribution of days-to-accept on this data:
- Within 7 days: 79%
- Within 14 days: 100%

Using a shorter window understates acceptance for recent cohorts (they look artificially low because they haven't had time yet). Using a longer window throws data away without adding signal.

**Edge cases:**
- Anchored on `sent_at` (cohort metric: "of gifts sent on day X, what fraction were eventually accepted?"). Anchoring on `accepted_at` would give 100% trivially.
- Gifts within the 14-day window are excluded from both numerator and denominator. A separate "pipeline" view of in-flight gifts is a sensible follow-up but kept out of this metric definition.
- 12 lifecycle-anomaly rows excluded.

### 3. Sender LTV — `fct_sender_ltv`

Two complementary calculations, both in the same table:

**`gmv_lifetime_usd`** — cumulative GMV per sender, all-time. Simple, but not comparable across cohorts (senders active longer mechanically have higher LTV).
*Use for:* Sales/CS account prioritization, Finance reporting.

**`gmv_first_180d_usd`** — GMV in the first 180 days of the sender's activity. Cohort-comparable. NULL if the sender has less than 180 days of tenure.
*Use for:* Growth experiments, onboarding A/B tests, channel-ROI analysis.

**Why "first activity" is `MIN(batch_created_at)` and not `users.created_at`:** 28 of 250 active senders (~11%) have `users.created_at` AFTER their first sent batch, which is impossible if `users.created_at` were a true signup timestamp. We treat the first batch as a more reliable activity anchor.

---

## Behavioral segmentation: `int_sender_segment`

Three companies (~6% of customers) generate ~71% of all gifts but only ~24% of GMV, with acceptance rates near 10%. Their pattern is operationally distinct from "relational" corporate gifting. Without segmenting, every aggregate metric is dominated by their behavior and exec dashboards become misleading.

Rather than hardcoding company names (doesn't scale, breaks with new customers), this model classifies behaviorally:

A company is `mass_outreach` if it has ≥100 total gifts sent AND EITHER:
- median gifts-per-batch ≥ 50, OR
- matured acceptance rate ≤ 20%

Otherwise `targeted`. Companies with <100 gifts default to `targeted` (insufficient signal).

Validation: this rule cleanly recovers the three expected mass-outreach companies (LeadFlow, OutreachPro, DemandGen) and classifies the remaining 44 as targeted, matching observed behavior. The rule is auditable and easy to adjust.

This is labeled v1. Future iterations could add: drift detection (is a company sliding toward bulk behavior?), seasonality-adjusted acceptance, batch-size variance, etc.

---

## Edge cases & data quality issues handled

Two distinct kinds of issues, tracked with separate flags:

**`has_lifecycle_anomaly`** — logically impossible orderings. Marts EXCLUDE these.

| Issue | Count | Handling |
|---|---|---|
| `accepted_at < opened_at` (impossible) | 11 gifts | Flagged + excluded from marts |
| `accepted_at` populated but `opened_at` NULL | 1 gift | Same flag, same handling |

**`is_lifecycle_censored`** — lifecycle timestamps truncated to the snapshot moment (`2025-12-31 23:59:59`). The dataset was snapshotted at year-end, and gifts whose lifecycle hadn't completed yet had their pending timestamps set to the snapshot moment. The underlying acceptance and GMV are real; only the "when" is imprecise. Marts KEEP these rows.

| Field with sentinel | Count |
|---|---|
| `opened_at` = sentinel | 92 |
| `accepted_at` = sentinel | 584 |
| `shipped_at` = sentinel | 823 |
| `delivered_at` = sentinel | 1,336 |

**Known distortion from keeping censored rows:** The date 2025-12-31 carries ~$51k in GMV (3% of annual total, ~10x the typical daily total). Consumers cutting GMV at daily/weekly grain near year-end should aggregate to monthly grain, or filter `is_lifecycle_censored` in `int_gifts_enriched`, or annotate the chart. Aggregations at monthly+ grain absorb the distortion naturally. `fct_acceptance_rate` is unaffected because it's anchored on `sent_at` (always real) and acceptance is a boolean.

**Other issues**:

| Issue | Handling | Where |
|---|---|---|
| 28 users with `user_created_at` after their first sent batch | Use `MIN(batch_created_at)` as activity anchor; do NOT use `user_created_at` for cohorting | `fct_sender_ltv` |
| `final_amount_cents = 0` for all non-accepted gifts | Verified in EDA; we filter on `accepted_at IS NOT NULL` for clarity, not on amount | `fct_gmv_daily` |
| `scheduled_send_at` populated on ~19% of batches | We trust `gift.sent_at` as the authoritative "when did it actually go out" — never use `batch_created_at` for time-based filtering | All marts |
| Three mass-outreach companies dominate aggregates | Behavioral segmentation; ALL metric tables expose `sender_segment` so consumers can split | `int_sender_segment` |

---

## Known limitations

- **Only one year of data (2025).** Cannot compute YoY growth or distinguish trend from seasonality. The Q4 spike is clear in 2025 but we can't confirm it's a recurring pattern.
- **No cost data.** Cannot compute true unit economics (margin per gift, per company, per segment). This matters for prioritization decisions around mass_outreach.
- **No event-level data beyond the five-stage funnel.** Cannot diagnose why ~17% of opens in the targeted segment fail to convert to acceptance (UI friction? address collection? recipient lost interest?).
- **`users.created_at` integrity issue** noted above; would flag to the data engineering team to investigate the upstream source.
- **Currency is assumed USD** because only one is present, but international expansion plans should formalize a `currency_code` column on `gifts` and a multi-currency GMV definition.

---

## What I'd prioritize next

1. **Daily monitoring layer.** A simple `fct_metrics_daily` rolling up GMV, acceptance rate, and active-senders count by segment, with 7d and 28d rolling averages. The current marts are designed for ad-hoc analysis; an exec dashboard needs a thinner, faster table.

2. **Acceptance funnel decomposition.** Funnel events between `sent → opened → accepted` to diagnose the targeted-segment ~17% "opened but didn't accept" gap. This requires either upstream event instrumentation or careful inference from `opened_at - accepted_at` distributions.

3. **Pre-Q4 readiness pacing.** A view that compares each customer's Aug–Oct activity to their Q4 historical share, flagging accounts likely to under-deliver vs forecast. Useful for CS proactive outreach.

4. **`fct_company_health`.** Rolled-up sender LTV, send cadence, swap rate, and acceptance-rate trend per company. Useful for CS health scoring and renewal prep.

5. **Data quality monitors.** Lightweight tests on the four issues documented above, alerting if anomaly counts grow week-over-week — explicitly called out as a responsibility of this role in the JD.
