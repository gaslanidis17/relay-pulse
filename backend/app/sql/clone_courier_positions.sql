-- One representative ONLINE location per courier per local hour, for the vehicle
-- availability map. Uses the same online-presence source and "real courier" day
-- gate as the vehicle availability calendar, so the dots on the map match the
-- calendar cell for that hour (no longer tied to heavy/large order pickups).
--
-- Day gate (drops multi-app / ghost sign-ins): completed >= 1 delivery that day
-- OR online > 15 minutes that day. {vehicle_filter_clause} filters vehicle_type.
WITH tz AS (
    SELECT COALESCE(MAX(CASE
        WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
        WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
        WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
        WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
        WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
        WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
        WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
        ELSE ap.timezone
    END), 'UTC') AS tzname
    FROM staging.purchases ap
    JOIN public.venues v ON ap.venue_id = v.venue_id
    WHERE v.city = '{city}'
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -7, '{date_to}'::DATE)
      AND ap.time_delivered::TIMESTAMP < DATEADD('day', 2, '{date_to}'::DATE)
),
sessions AS (
    SELECT
        a.courier_id,
        a.vehicle_type,
        a.minutes_online_total,
        a.attributed_session_location AS loc,
        CONVERT_TIMEZONE('UTC', t.tzname, a.start_time::TIMESTAMP) AS local_start
    FROM public.routemill_courier_location_data_aggregates a
    CROSS JOIN tz t
    WHERE a.city = '{city}'
      AND a.attributed_session_location IS NOT NULL
      AND a.start_time::TIMESTAMP >= DATEADD('day', -1, '{date_from}'::DATE)
      AND a.start_time::TIMESTAMP < DATEADD('day', 2, '{date_to}'::DATE)
),
day_online AS (
    SELECT courier_id, local_start::DATE AS local_date,
           SUM(minutes_online_total) AS online_min
    FROM sessions
    GROUP BY courier_id, local_start::DATE
),
day_deliv AS (
    SELECT
        fcd.courier_id,
        CONVERT_TIMEZONE('UTC', t.tzname, fcd.time_delivery_completed_utc::TIMESTAMP)::DATE AS local_date,
        COUNT(*) AS deliveries
    FROM intermediate.f_courier_deliveries_core fcd
    CROSS JOIN tz t
    WHERE fcd.fleet_city = '{city}'
      AND fcd.time_delivery_completed_utc IS NOT NULL
      AND fcd.time_delivery_completed_utc::TIMESTAMP >= DATEADD('day', -1, '{date_from}'::DATE)
      AND fcd.time_delivery_completed_utc::TIMESTAMP < DATEADD('day', 2, '{date_to}'::DATE)
    GROUP BY fcd.courier_id,
             CONVERT_TIMEZONE('UTC', t.tzname, fcd.time_delivery_completed_utc::TIMESTAMP)::DATE
),
qualified AS (
    SELECT courier_id, local_date FROM day_online WHERE online_min > 15
    UNION
    SELECT courier_id, local_date FROM day_deliv WHERE deliveries >= 1
),
ranked AS (
    SELECT
        s.courier_id,
        s.vehicle_type,
        s.loc,
        HOUR(s.local_start) AS hour_of_day,
        ROW_NUMBER() OVER (
            PARTITION BY s.courier_id, HOUR(s.local_start)
            ORDER BY s.local_start ASC
        ) AS rn
    FROM sessions s
    JOIN qualified q
      ON s.courier_id = q.courier_id
     AND s.local_start::DATE = q.local_date
    WHERE s.local_start::DATE >= '{date_from}'::DATE
      AND s.local_start::DATE <= '{date_to}'::DATE
      AND s.vehicle_type IS NOT NULL
      {vehicle_filter_clause}
)
SELECT
    courier_id,
    COALESCE(vehicle_type, 'UNKNOWN') AS vehicle_type,
    hour_of_day,
    ROUND(loc[1]::FLOAT, 5) AS lat,
    ROUND(loc[0]::FLOAT, 5) AS lon
FROM ranked
WHERE rn = 1
  AND loc[0] IS NOT NULL
  AND loc[1] IS NOT NULL
LIMIT 60000
