WITH tz_purchases AS (
    SELECT
        ap.id AS purchase_id,
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
            ELSE 'NONE'
        END AS capability_group,
        CASE WHEN ctg.is_duplicate = TRUE THEN 1 ELSE 0 END AS is_cloned,
        CASE WHEN COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_heavy,
        CASE WHEN COALESCE(fcd.IS_LARGE_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_large,
        ctg."TIME_TO_LAST_ACCEPT" AS ttla_sec
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
    LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id
    WHERE v.city = '{city}'
      AND ap.delivery_method = 'homedelivery'
      AND ap.delivery_provider = 'relay'
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
      {size_filter_clause}
      {weight_tier_clause}
)
SELECT
    confirmed_date,
    COUNT(DISTINCT purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN is_heavy = 1 THEN purchase_id END) AS heavy_count,
    COUNT(DISTINCT CASE WHEN is_large = 1 THEN purchase_id END) AS large_count,
    COUNT(DISTINCT CASE WHEN is_cloned = 1 THEN purchase_id END) AS cloned_count,
    ROUND(
        COUNT(DISTINCT CASE WHEN is_cloned = 1 THEN purchase_id END)
        / NULLIF(COUNT(DISTINCT purchase_id), 0) * 100, 1
    ) AS clone_rate_pct,
    ROUND(AVG(ttla_sec), 0) AS avg_ttla_sec,
    COUNT(DISTINCT CASE WHEN capability_group = 'WEIGHT_L' THEN purchase_id END) AS weight_l_count,
    COUNT(DISTINCT CASE WHEN capability_group = 'WEIGHT_XL' THEN purchase_id END) AS weight_xl_count,
    COUNT(DISTINCT CASE WHEN capability_group = 'WEIGHT_XXL' THEN purchase_id END) AS weight_xxl_count,
    COUNT(DISTINCT CASE WHEN capability_group = 'WEIGHT_XXXL' THEN purchase_id END) AS weight_xxxl_count
FROM tz_purchases
GROUP BY confirmed_date
ORDER BY confirmed_date
