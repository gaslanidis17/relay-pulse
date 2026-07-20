WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM INTERMEDIATE.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT(DISTINCT fp.purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN fcd.IS_HEAVY_DELIVERY THEN fp.purchase_id END) AS heavy_count,
    COUNT(DISTINCT CASE WHEN sla.is_late AND fcd.IS_HEAVY_DELIVERY THEN fp.purchase_id END) AS heavy_late,
    COUNT(DISTINCT CASE WHEN fcd.IS_LARGE_DELIVERY THEN fp.purchase_id END) AS large_count,
    COUNT(DISTINCT CASE WHEN sla.is_late AND fcd.IS_LARGE_DELIVERY THEN fp.purchase_id END) AS large_late,
    ROUND(AVG(
        CASE WHEN fp.is_preorder = 'False'
              AND fp.delivery_method = 'homedelivery'
              AND fp.time_delivered_utc IS NOT NULL
              AND (fp.delivery_provider_type <> 'self' OR fp.delivery_provider_type IS NULL)
              AND fp.delivery_time_sec > 300
              AND fp.delivery_time_sec < 10800
             THEN fp.delivery_time_sec / 60.0
             ELSE NULL
        END
    ), 1) AS avg_delivery_time
FROM INTERMEDIATE.f_purchases AS fp
LEFT JOIN purchase_sla AS sla ON sla.purchase_id = fp.purchase_id
LEFT JOIN INTERMEDIATE.F_COURIER_DELIVERIES AS fcd ON fcd.PURCHASE_ID = fp.purchase_id
WHERE fp.venue_country = '{country}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fp.venue_operations_area = '{city}'
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1
ORDER BY 1
