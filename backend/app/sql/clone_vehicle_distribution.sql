WITH tz_tasks AS (
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
        cdt.worker_id,
        rw.vehicle_type,
        cdt.started_at::TIMESTAMP AS task_start,
        cdt.arrived_at::TIMESTAMP AS task_end,
        ap.id AS purchase_id
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
    LEFT JOIN public.routemill_tasks AS cdt
        ON ctg.id = cdt.task_group_id AND cdt.pickup_task = FALSE
    LEFT JOIN public.routemill_worker AS rw ON cdt.worker_id = rw.id
    WHERE v.city = '{city}'
      AND ap.delivery_method = 'homedelivery'
      AND ap.delivery_provider = 'relay'
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
      AND cdt.worker_id IS NOT NULL
      AND rw.vehicle_type IS NOT NULL
)
SELECT
    confirmed_date,
    vehicle_type,
    COUNT(DISTINCT worker_id) AS courier_count,
    COUNT(DISTINCT purchase_id) AS order_count,
    ROUND(SUM(
        DATEDIFF('second', task_start, task_end) / 3600.0
    ), 1) AS total_active_hours
FROM tz_tasks
WHERE task_start IS NOT NULL AND task_end IS NOT NULL
  AND task_end > task_start
GROUP BY confirmed_date, vehicle_type
ORDER BY confirmed_date, vehicle_type
