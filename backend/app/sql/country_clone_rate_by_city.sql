-- Country daily clone counts BROKEN OUT BY CITY (operations area), on the same
-- INTERMEDIATE.f_purchases spine as country_clone_rate_total.sql. Identical WHERE
-- clause + clone definition; the only addition is the city dimension.
--
-- RECONCILIATION: each purchase is assigned a SINGLE city via
-- MIN(venue_operations_area) OVER (PARTITION BY purchase_id) so purchases that
-- span more than one operations area are not double-counted (see
-- country_daily_rates_by_city.sql for the full rationale). Summed over all cities
-- this reconciles EXACTLY to country_clone_rate_total.sql. A clone is a purchase
-- whose task group is flagged duplicate (presentation.task_groups_enriched
-- .is_duplicate); task_groups_enriched fans out per purchase, so both counts use
-- COUNT(DISTINCT fp.purchase_id) to avoid inflation.
WITH fp_city AS (
    SELECT
        fp.purchase_id,
        fp.time_confirmed_utc,
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
    COUNT(DISTINCT CASE WHEN ctg.is_duplicate = TRUE THEN fpc.purchase_id END) AS cloned_count
FROM fp_city AS fpc
LEFT JOIN presentation.task_groups_enriched AS ctg ON ctg.purchase_id = fpc.purchase_id
GROUP BY 1, 2
ORDER BY 1, 2
