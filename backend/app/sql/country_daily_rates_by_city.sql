-- Country daily total lateness + rotten counts BROKEN OUT BY CITY (operations
-- area), on the same INTERMEDIATE.f_purchases spine as
-- country_daily_rates_total.sql. Identical WHERE clause + metric definitions; the
-- only addition is the city dimension.
--
-- RECONCILIATION: a small fraction of purchases have rows under more than one
-- venue_operations_area. A naive GROUP BY venue_operations_area with
-- COUNT(DISTINCT purchase_id) would then count such a purchase once PER area
-- (~1% overcount vs the country total). To partition purchases DISJOINTLY we
-- assign each purchase a SINGLE city via MIN(venue_operations_area) OVER
-- (PARTITION BY purchase_id) (MIN() OVER ignores NULLs, so a purchase keeps a
-- real area when it has one, else falls to 'Unknown'). Summed over all cities
-- this reconciles EXACTLY to country_daily_rates_total.sql. Lateness uses the
-- official SLA is_late flag; Rotten = time_to_last_accept over the threshold.
WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM INTERMEDIATE.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
),
fp_city AS (
    SELECT
        fp.purchase_id,
        fp.time_confirmed_utc,
        fp.time_to_last_accept_sec,
        COALESCE(MIN(fp.venue_operations_area) OVER (PARTITION BY fp.purchase_id), 'Unknown') AS city
    FROM INTERMEDIATE.f_purchases AS fp
    WHERE fp.venue_country = '{country}'
      AND fp.status = 'delivered'
      AND (NOT fp.is_drive OR fp.is_drive IS NULL)
      AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND fp.time_confirmed_utc < CURRENT_DATE()
)
SELECT
    TO_CHAR(TO_DATE(fpc.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    fpc.city AS city,
    COUNT(DISTINCT fpc.purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN sla.is_late THEN fpc.purchase_id END) AS late_count,
    COUNT(DISTINCT CASE WHEN fpc.time_to_last_accept_sec / 60.0 >= {rotten_threshold_min} THEN fpc.purchase_id END) AS rotten_count
FROM fp_city AS fpc
LEFT JOIN purchase_sla AS sla ON sla.purchase_id = fpc.purchase_id
GROUP BY 1, 2
ORDER BY 1, 2
