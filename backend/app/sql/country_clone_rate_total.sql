-- Country-wide daily clone counts (drive orders excluded), on the same
-- INTERMEDIATE.f_purchases spine as country_daily_rates_total.sql so the
-- denominator, date bucketing (UTC confirmed_date) and drive-exclusion match
-- the Region tab's other metrics. A clone is a purchase whose task group is
-- flagged duplicate (presentation.task_groups_enriched.is_duplicate), the same
-- definition the city Clone Rate tab uses. task_groups_enriched can fan out per
-- purchase, so both counts use COUNT(DISTINCT fp.purchase_id) to avoid inflation.
SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT(DISTINCT fp.purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN ctg.is_duplicate = TRUE THEN fp.purchase_id END) AS cloned_count
FROM INTERMEDIATE.f_purchases AS fp
LEFT JOIN presentation.task_groups_enriched AS ctg ON ctg.purchase_id = fp.purchase_id
WHERE fp.venue_country = '{country}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1
ORDER BY 1
