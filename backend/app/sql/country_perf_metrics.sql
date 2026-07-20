SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    fp.venue_operations_area AS city,
    CASE WHEN fcd."IS_HEAVY_DELIVERY" THEN 'Yes' ELSE 'No' END AS is_heavy,
    fcd."COMPLETED_WITH_VEHICLE_TYPE" AS vehicle_type,
    COUNT(DISTINCT fp.purchase_id) AS order_count,
    DIV0(
        SUM(fcd."COUNT_TIMES_TASKS_ACCEPTED"),
        SUM(fcd."COUNT_TIMES_TASKS_SERVED")
    ) AS task_acceptance_rate,
    AVG(fp.time_to_last_accept_sec) AS avg_ttla_sec,
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
LEFT JOIN INTERMEDIATE.F_COURIER_DELIVERIES AS fcd
    ON fcd.PURCHASE_ID = fp.purchase_id
WHERE fp.venue_country = '{country}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fcd."COMPLETED_WITH_VEHICLE_TYPE" IS NOT NULL
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4
