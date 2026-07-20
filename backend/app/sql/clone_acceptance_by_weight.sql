SELECT
    TO_CHAR(TO_DATE(
        CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, ap.time_delivered::TIMESTAMP)
    ), 'YYYY-MM-DD') AS confirmed_date,
    CASE
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_L%' ESCAPE '^' THEN 'WEIGHT_L'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XL%' ESCAPE '^' THEN 'WEIGHT_XL'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXL%' ESCAPE '^' THEN 'WEIGHT_XXL'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXXL%' ESCAPE '^' THEN 'WEIGHT_XXXL'
        ELSE 'Other'
    END AS capability_group,
    COUNT(DISTINCT ap.id) AS order_count,
    ROUND(AVG(CASE WHEN ctg.is_duplicate = TRUE THEN 1.0 ELSE 0.0 END) * 100, 1) AS cloned_pct,
    DIV0(
        SUM(ctss.is_task_accepted::INT),
        SUM(ctss.is_task_served::INT)
    ) AS acceptance_rate,
    ROUND(AVG(ctg."TIME_TO_LAST_ACCEPT"), 0) AS avg_ttla_sec
FROM staging.purchases AS ap
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id
LEFT JOIN public.routemill_tasks AS ct ON ct.task_group_id = ctg.id
LEFT JOIN COURIER.TASK_START_STATISTICS AS ctss ON ct.id = ctss."TASK_ID"
WHERE v.city = '{city}'
  AND ap.delivery_method = 'homedelivery'
  AND ap.delivery_provider = 'relay'
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
  {size_filter_clause}
  AND CASE
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_L%' ESCAPE '^' THEN 'WEIGHT_L'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XL%' ESCAPE '^' THEN 'WEIGHT_XL'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXL%' ESCAPE '^' THEN 'WEIGHT_XXL'
        WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXXL%' ESCAPE '^' THEN 'WEIGHT_XXXL'
        ELSE 'Other'
      END <> 'Other'
GROUP BY 1, 2
ORDER BY 1, 2
