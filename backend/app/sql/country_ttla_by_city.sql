-- Country daily TTLA (Task to Last Accept) inputs BROKEN OUT BY CITY (operations
-- area), on the same INTERMEDIATE.f_purchases spine as country_ttla_total.sql.
-- IDENTICAL WHERE clause + TTLA metric (same on-demand exclusions: is_drive=FALSE,
-- is_preorder=FALSE, is_time_slot_order=FALSE); the only addition is the city
-- dimension. Because the WHERE is identical, total vs by_city still reconcile.
--
-- TTLA is an order-weighted MEAN, so we emit the per-(day, city) SUM of TTLA
-- seconds (ttla_sec_sum) and the COUNT of orders the mean is taken over
-- (ttla_order_count); the frontend forms TTLA = Σ seconds / Σ orders and
-- aggregates an order-weighted mean across cities/days. Higher = slower to accept.
--
-- RECONCILIATION: a small fraction of purchases have rows under more than one
-- venue_operations_area. We assign each purchase a SINGLE city via
-- MIN(venue_operations_area) OVER (PARTITION BY purchase_id) (MIN() OVER ignores
-- NULLs; COALESCE falls back to 'Unknown'), keeping ALL rows. Because every row of
-- a purchase gets that same assigned city, the per-city SUM/COUNT summed over all
-- cities reconciles EXACTLY to country_ttla_total.sql. Do NOT inner-filter to the
-- curated city list. (See country_ttla_total.sql for the metric + filter notes,
-- including the UTC confirmed_date windowing that aligns TTLA with the other
-- Region metrics.)
--
-- TTLA CALCULATION MODE (placeholders ttla_cte_prepend / ttla_join / ttla_expr):
--   default        -> f_purchases.time_to_last_accept_sec (no CTE/join). fp_city
--                     selects CAST(fp.time_to_last_accept_sec AS DOUBLE) AS
--                     ttla_sec, so the default SQL is byte-identical to the
--                     pre-mode version (COUNT/SUM skip NULLs, no not-null filter).
--   first_courier  -> the 1st (original) task group's TIME_TO_LAST_ACCEPT, via a
--   fixed            `tg_per_purchase` CTE (one row per purchase, country-scoped —
--                     city=None since by-city covers ALL operations areas) LEFT
--                     JOINed into fp_city. tg_per_purchase is PREPENDED before
--                     fp_city (ttla_cte_prepend) because fp_city itself joins it
--                     (SQL forbids forward CTE references); ttla_expr becomes
--                     tg.first_ttla / tg.fixed_ttla. See services/ttla_filters.py
--                     (ttla_mode_fragments / country_ttla_population_clause).
WITH{ttla_cte_prepend} fp_city AS (
    SELECT
        fp.purchase_id,
        fp.time_confirmed_utc,
        {ttla_expr} AS ttla_sec,
        COALESCE(MIN(fp.venue_operations_area) OVER (PARTITION BY fp.purchase_id), 'Unknown') AS city
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
)
SELECT
    TO_CHAR(TO_DATE(fpc.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    fpc.city AS city,
    COUNT(fpc.ttla_sec) AS ttla_order_count,
    ROUND(SUM(fpc.ttla_sec), 2) AS ttla_sec_sum
FROM fp_city AS fpc
GROUP BY 1, 2
HAVING COUNT(DISTINCT fpc.purchase_id) > 0
ORDER BY 1, 2
