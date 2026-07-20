-- Per-city daily TTLA (Task to Last Accept) inputs — the single-city variant of
-- country_ttla_total.sql for the Country tab's per-city /analytics endpoint
-- (mirrors the single-city country_daily_rates.sql). Same INTERMEDIATE.f_purchases
-- spine, TTLA metric, filters and UTC confirmed_date windowing as the total; the
-- only addition is the venue_operations_area = '{city}' filter.
--
-- Returns per day the SUM of TTLA seconds (ttla_sec_sum) + the order count the
-- mean is taken over (ttla_order_count); TTLA = ttla_sec_sum / ttla_order_count
-- seconds (order-weighted mean, == AVG(CAST(TIME_TO_LAST_ACCEPT_SEC AS DOUBLE
-- PRECISION)) over the same non-NULL rows). See country_ttla_total.sql for the
-- metric + filter rationale (status IN ('delivered','refunded'),
-- delivery_provider_type = 'relay' plus the pure on-demand exclusions is_drive=FALSE
-- / is_preorder=FALSE / is_time_slot_order=FALSE — 'relay' alone does NOT exclude
-- Relay Express — and confirmed_date windowing). This is IDENTICAL to the total's
-- WHERE plus the venue_operations_area filter, so per-city reconciles to the
-- master. Like the other single-city Country files this uses the plain (non
-- canonical) cache, keyed by city + lookback.
--
-- TTLA CALCULATION MODE (placeholders ttla_cte_outer / ttla_join / ttla_expr): identical
-- to country_ttla_total.sql, except the helper CTE is scoped to THIS city
-- (city='{city}') to cut the task-group aggregation. default resolves to empty
-- CTE/join + CAST(fp.time_to_last_accept_sec AS DOUBLE) so the default SQL is
-- byte-identical to the pre-mode version (COUNT/SUM skip NULLs). See
-- services/ttla_filters.py (ttla_mode_fragments / country_ttla_population_clause).
{ttla_cte_outer}SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT({ttla_expr}) AS ttla_order_count,
    ROUND(SUM({ttla_expr}), 2) AS ttla_sec_sum
FROM INTERMEDIATE.f_purchases AS fp
{ttla_join}
WHERE fp.venue_country = '{country}'
  AND fp.venue_operations_area = '{city}'
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
