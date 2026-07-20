-- Heavy/large orders aggregated by venue location per local hour-of-day, for the
-- orders map. {size_filter_clause} applies the heavy/large/heavy|large toggle.
WITH tz_purchases AS (
    SELECT
        ap.id AS purchase_id,
        ap.venue_name,
        ap.venue_lat,
        ap.venue_long,
        CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, ap.time_delivered::TIMESTAMP) AS local_delivered,
        CASE WHEN COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_heavy,
        CASE WHEN COALESCE(fcd.IS_LARGE_DELIVERY, FALSE) THEN 1 ELSE 0 END AS is_large
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id
    WHERE v.city = '{city}'
      AND ap.delivery_method = 'homedelivery'
      AND ap.delivery_provider = 'relay'
      AND ap.venue_lat IS NOT NULL
      AND ap.venue_long IS NOT NULL
      AND ap.time_delivered::TIMESTAMP >= '{date_from}'::DATE
      AND ap.time_delivered::TIMESTAMP < DATEADD('day', 1, '{date_to}'::DATE)
      {size_filter_clause}
)
SELECT
    MAX(venue_name) AS venue_name,
    ROUND(venue_lat, 6) AS lat,
    ROUND(venue_long, 6) AS lon,
    HOUR(local_delivered) AS hour_of_day,
    COUNT(DISTINCT purchase_id) AS orders,
    SUM(is_heavy) AS heavy_orders,
    SUM(is_large) AS large_orders
FROM tz_purchases
WHERE local_delivered::DATE >= '{date_from}'::DATE
  AND local_delivered::DATE <= '{date_to}'::DATE
GROUP BY venue_lat, venue_long, HOUR(local_delivered)
ORDER BY orders DESC
LIMIT 50000
