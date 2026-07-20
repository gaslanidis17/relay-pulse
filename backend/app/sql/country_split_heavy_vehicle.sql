SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    fcd.COMPLETED_WITH_VEHICLE_TYPE AS vehicle_type,
    COUNT(DISTINCT fp.purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN fp.is_purchase_split_by_ops THEN fp.purchase_id END) AS split_count
FROM INTERMEDIATE.f_purchases AS fp
LEFT JOIN INTERMEDIATE.F_COURIER_DELIVERIES AS fcd
    ON fcd.PURCHASE_ID = fp.purchase_id
WHERE fp.venue_country = '{country}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fp.venue_operations_area = '{city}'
  AND fcd.IS_HEAVY_DELIVERY
  AND fcd.COMPLETED_WITH_VEHICLE_TYPE IS NOT NULL
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1, 2
ORDER BY 1, 2
