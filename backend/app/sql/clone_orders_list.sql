WITH tz_purchases AS (
    SELECT
        ap.id AS purchase_id,
        ap.venue_name,
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
        ap.time_delivered::TIMESTAMP AS delivered_at_utc,
        ctg.id AS task_group_id,
        ctg.is_duplicate AS is_duplicate,
        ctg."TIME_TO_LAST_ACCEPT" AS ttla_sec,
        ctg."SHOWN_TO_COURIERS_COUNT" AS shown_to_couriers,
        ctg."VEHICLE_TYPE" AS vehicle_type,
        CASE
            WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_L%' ESCAPE '^' THEN 'WEIGHT_L'
            WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XL%' ESCAPE '^' THEN 'WEIGHT_XL'
            WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXL%' ESCAPE '^' THEN 'WEIGHT_XXL'
            WHEN ctg.required_capabilities::TEXT LIKE '%WEIGHT^_XXXL%' ESCAPE '^' THEN 'WEIGHT_XXXL'
            ELSE 'NONE'
        END AS capability_group,
        CASE WHEN COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_heavy,
        CASE WHEN COALESCE(fcd.IS_LARGE_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_large
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
    purchase_id,
    MAX(venue_name) AS venue_name,
    MAX(confirmed_date) AS confirmed_date,
    MAX(capability_group) AS capability_group,
    MAX(is_heavy) AS is_heavy,
    MAX(is_large) AS is_large,
    COUNT(DISTINCT task_group_id) AS task_group_count,
    COUNT(DISTINCT CASE WHEN is_duplicate = TRUE THEN task_group_id END) AS clone_count,
    ROUND(MAX(ttla_sec), 0) AS ttla_sec,
    MAX(shown_to_couriers) AS shown_to_couriers,
    LISTAGG(DISTINCT vehicle_type, ' | ') WITHIN GROUP (ORDER BY vehicle_type) AS vehicle_types
FROM tz_purchases
GROUP BY purchase_id
HAVING COUNT(DISTINCT CASE WHEN is_duplicate = TRUE THEN task_group_id END) > 0
ORDER BY MAX(delivered_at_utc) DESC
LIMIT 2000
