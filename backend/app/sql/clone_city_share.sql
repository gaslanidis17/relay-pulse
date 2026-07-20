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
        CASE WHEN COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_heavy,
        CASE WHEN COALESCE(fcd.IS_LARGE_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_large
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id
    WHERE v.city = '{city}'
      AND ap.delivery_method = 'homedelivery'
      AND ap.delivery_provider = 'relay'
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
)
SELECT
    confirmed_date,
    COUNT(DISTINCT purchase_id) AS all_orders,
    SUM(is_heavy) AS heavy_count,
    SUM(is_large) AS large_count
FROM tz_purchases
GROUP BY confirmed_date
ORDER BY confirmed_date
