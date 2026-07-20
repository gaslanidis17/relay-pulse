-- Country daily heavy/large lateness BROKEN OUT BY CITY (operations area), on the
-- same INTERMEDIATE.f_purchases spine as country_hl_lateness_total.sql. Identical
-- WHERE clause + metric definitions; the only addition is the city dimension.
--
-- RECONCILIATION: each purchase is assigned a SINGLE city via
-- MIN(venue_operations_area) OVER (PARTITION BY purchase_id) so purchases that
-- span more than one operations area are not double-counted (see
-- country_daily_rates_by_city.sql for the full rationale). Summed over all cities
-- this reconciles EXACTLY to country_hl_lateness_total.sql (heavy_count,
-- heavy_late, large_count, large_late). Heavy/large flags live on the delivery
-- table (F_COURIER_DELIVERIES), which fans out per purchase; COUNT(DISTINCT
-- purchase_id) collapses that fan-out exactly as the country-total file does.
WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM INTERMEDIATE.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
),
fp_city AS (
    SELECT
        fp.purchase_id,
        fp.time_confirmed_utc,
        fp.is_preorder,
        fp.delivery_method,
        fp.time_delivered_utc,
        fp.delivery_provider_type,
        fp.delivery_time_sec,
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
    COUNT(DISTINCT CASE WHEN fcd.IS_HEAVY_DELIVERY THEN fpc.purchase_id END) AS heavy_count,
    COUNT(DISTINCT CASE WHEN sla.is_late AND fcd.IS_HEAVY_DELIVERY THEN fpc.purchase_id END) AS heavy_late,
    COUNT(DISTINCT CASE WHEN fcd.IS_LARGE_DELIVERY THEN fpc.purchase_id END) AS large_count,
    COUNT(DISTINCT CASE WHEN sla.is_late AND fcd.IS_LARGE_DELIVERY THEN fpc.purchase_id END) AS large_late,
    ROUND(AVG(
        CASE WHEN fpc.is_preorder = 'False'
              AND fpc.delivery_method = 'homedelivery'
              AND fpc.time_delivered_utc IS NOT NULL
              AND (fpc.delivery_provider_type <> 'self' OR fpc.delivery_provider_type IS NULL)
              AND fpc.delivery_time_sec > 300
              AND fpc.delivery_time_sec < 10800
             THEN fpc.delivery_time_sec / 60.0
             ELSE NULL
        END
    ), 1) AS avg_delivery_time
FROM fp_city AS fpc
LEFT JOIN purchase_sla AS sla ON sla.purchase_id = fpc.purchase_id
LEFT JOIN INTERMEDIATE.F_COURIER_DELIVERIES AS fcd ON fcd.PURCHASE_ID = fpc.purchase_id
GROUP BY 1, 2
ORDER BY 1, 2
