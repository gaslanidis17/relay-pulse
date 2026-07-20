-- Country-wide daily Task to Last Accept (TTLA) inputs, on the same
-- INTERMEDIATE.f_purchases spine as country_adt_total.sql, so TTLA lines up with
-- the Region tab's other metrics.
--
-- TTLA = the seconds elapsed before the courier who ultimately completes pickup
-- accepted the task (if a courier accepts then unassigns without completing
-- pickup, the count continues from the unassign point until the next courier
-- accepts AND completes pickup). Source column: TIME_TO_LAST_ACCEPT_SEC.
--
-- Like ADT it is an order-weighted MEAN, so we return per day the SUM of TTLA
-- seconds (ttla_sec_sum) and the COUNT of orders the mean is taken over
-- (ttla_order_count) rather than a precomputed average, so the frontend can
-- aggregate an order-weighted mean across days/cities/countries
-- (Σ seconds / Σ orders) and never has to average daily means. Because
-- ttla_sec_sum / ttla_order_count == AVG(CAST(TIME_TO_LAST_ACCEPT_SEC AS DOUBLE
-- PRECISION)) over the same (non-NULL) rows, this equals the authoritative TTLA
-- metric exactly. COUNT(col)/SUM(col) both ignore NULL TTLA, matching AVG.
--
-- FILTERS (pure ON-DEMAND Relay courier population, matching the Retail-TTLA tab —
--   DISTINCT from ADT's homedelivery/5min-3h clamp):
--   status IN ('delivered','refunded'); delivery_provider_type = 'relay'; and — to
--   isolate on-demand courier orders — is_drive = FALSE (excludes Relay Express),
--   is_preorder = FALSE (excludes scheduled preorders) and is_time_slot_order =
--   FALSE (excludes time-slot orders); plus HAVING COUNT(DISTINCT purchase_id) > 0.
--   NOTE: Drive orders carry delivery_provider_type='relay' AND is_drive=TRUE, so
--   'relay' alone does NOT exclude Drive (the previous definition wrongly claimed it
--   did). Empirically Drive was ~32% of KAZ TTLA orders and inflated KAZ avg TTLA
--   from 161.7s to 198.4s (flipping KAZ over its 174s target), so excluding Drive
--   materially corrects the metric. WINDOWING, however, matches the
--   ADT/Region family: we bucket + filter on time_confirmed_utc (UTC
--   confirmed_date) with the DATEADD lookback + today-exclusive upper bound, NOT
--   the metric's original delivered-date / current-month window, so TTLA aligns
--   day-for-day with the other Region metrics and reuses the same deep-cache
--   date machinery. (Refunded orders that were accepted but never delivered still
--   have a confirmed date, so confirmed_date bucketing keeps them too.)
--
-- RECONCILIATION: this is the country total; country_ttla_by_city.sql breaks the
-- same SUM/COUNT out by operations area (one city per purchase), so summing the
-- city seconds/orders reconciles EXACTLY to these totals.
--
-- TTLA CALCULATION MODE (placeholders ttla_cte_outer / ttla_join / ttla_expr):
--   default        -> f_purchases.time_to_last_accept_sec (no CTE/join). The
--                     placeholders resolve to empty + CAST(... AS DOUBLE), so the
--                     default SQL is byte-identical to the pre-mode version
--                     (COUNT/SUM skip NULLs, so no explicit not-null filter).
--   first_courier  -> the 1st (original) task group's TIME_TO_LAST_ACCEPT, via a
--   fixed            `tg_per_purchase` CTE (one row per purchase, scoped to THIS
--                     query's f_purchases population by a semi-join) LEFT JOINed
--                     in; ttla_expr becomes tg.first_ttla / tg.fixed_ttla. The
--                     CTE is country-scoped (city=None) for this total. See
--                     services/ttla_filters.py (ttla_mode_fragments /
--                     country_ttla_population_clause) for the fragment text.
{ttla_cte_outer}SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT({ttla_expr}) AS ttla_order_count,
    ROUND(SUM({ttla_expr}), 2) AS ttla_sec_sum
FROM INTERMEDIATE.f_purchases AS fp
{ttla_join}
WHERE fp.venue_country = '{country}'
  AND fp.status IN ('delivered', 'refunded')
  AND fp.delivery_provider_type = 'relay'
  AND fp.is_drive = FALSE
  AND fp.is_preorder = FALSE
  AND fp.is_time_slot_order = FALSE
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1
HAVING COUNT(DISTINCT fp.purchase_id) > 0
ORDER BY 1
