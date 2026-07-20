-- Vehicle AVAILABILITY per day / hour / vehicle type, based on real online
-- presence (PUBLIC.ROUTEMILL_COURIER_LOCATION_DATA_AGGREGATES) instead of
-- task/order assignment. This counts couriers who were genuinely online and
-- available in an hour, even if they never received a task.
--
-- "Real courier" day gate (removes multi-app / ghost sign-ins): a courier only
-- counts on a given local day if they completed >= 1 delivery that day OR were
-- online > 15 minutes that day. Vehicle type comes from the online session.
-- {vehicle_filter_clause} filters on vehicle_type.
WITH tz AS (
    -- Resolve the city's IANA timezone once (remapping a few zones Snowflake
    -- does not recognise), so hourly buckets line up with the rest of the tab.
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
        CONVERT_TIMEZONE('UTC', t.tzname, a.start_time::TIMESTAMP) AS local_start
    FROM public.routemill_courier_location_data_aggregates a
    CROSS JOIN tz t
    WHERE a.city = '{city}'
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
)
SELECT
    TO_CHAR(s.local_start, 'YYYY-MM-DD') AS confirmed_date,
    HOUR(s.local_start) AS hour_of_day,
    s.vehicle_type,
    COUNT(DISTINCT s.courier_id) AS available_vehicles
FROM sessions s
JOIN qualified q
  ON s.courier_id = q.courier_id
 AND s.local_start::DATE = q.local_date
WHERE s.local_start::DATE >= '{date_from}'::DATE
  AND s.local_start::DATE <= '{date_to}'::DATE
  AND s.vehicle_type IS NOT NULL
  {vehicle_filter_clause}
GROUP BY confirmed_date, hour_of_day, s.vehicle_type
ORDER BY confirmed_date, hour_of_day, s.vehicle_type
