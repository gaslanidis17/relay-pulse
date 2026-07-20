-- Per-city daily total lateness + rotten counts (drive orders excluded).
-- Lateness uses the official SLA is_late flag (same source as the Country tab's
-- Heavy/Large Late %). Rotten = time_to_last_accept over the configured threshold.
WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM INTERMEDIATE.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT(DISTINCT fp.purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN sla.is_late THEN fp.purchase_id END) AS late_count,
    COUNT(DISTINCT CASE WHEN fp.time_to_last_accept_sec / 60.0 >= {rotten_threshold_min} THEN fp.purchase_id END) AS rotten_count
FROM INTERMEDIATE.f_purchases AS fp
LEFT JOIN purchase_sla AS sla ON sla.purchase_id = fp.purchase_id
WHERE fp.venue_country = '{country}'
  AND fp.venue_operations_area = '{city}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1
ORDER BY 1
