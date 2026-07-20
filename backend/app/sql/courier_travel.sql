WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
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
    ), 'YYYY-MM-DD') AS delivered_date,

    courier_pickup_tasks.worker_id AS pickup_worker_id,
    courier_dropoff_tasks.worker_id AS dropoff_worker_id,
    courier_dropoff_tasks_courier.vehicle_type AS courier_vehicle_type,

    ctg."PICKUP_TASK_NAVIGATOR_DISTANCE" AS pickup_distance_m,
    ctg."DROPOFF_TASK_NAVIGATOR_DISTANCE" AS dropoff_distance_m,

    CASE WHEN courier_pickup_tasks.pickup_task = TRUE
         THEN DATEDIFF('second',
              courier_pickup_tasks.started_at::TIMESTAMP,
              courier_pickup_tasks.arrived_at::TIMESTAMP) / 60.0
         ELSE NULL
    END AS pickup_arrival_min,

    CASE WHEN courier_dropoff_tasks.pickup_task = FALSE
         THEN DATEDIFF('second',
              courier_dropoff_tasks.started_at::TIMESTAMP,
              courier_dropoff_tasks.arrived_at::TIMESTAMP) / 60.0
         ELSE NULL
    END AS dropoff_arrival_min,

    CASE WHEN ctg.is_duplicate THEN TRUE ELSE FALSE END AS is_cloned,
    COALESCE(pe.is_bundled, FALSE) AS is_bundled

FROM staging.purchases AS ap
LEFT JOIN staging.purchases_enriched AS pe ON ap.id = pe.purchase_id
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN public.routemill_tasks AS courier_pickup_tasks
    ON ctg.id = courier_pickup_tasks.task_group_id
    AND courier_pickup_tasks.pickup_task = TRUE
LEFT JOIN public.routemill_tasks AS courier_dropoff_tasks
    ON ctg.id = courier_dropoff_tasks.task_group_id
    AND courier_dropoff_tasks.pickup_task = FALSE
LEFT JOIN public.routemill_worker AS courier_dropoff_tasks_courier
    ON courier_dropoff_tasks.worker_id = courier_dropoff_tasks_courier.id
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id

WHERE v.city = '{city}'
  AND ap.delivery_provider = 'relay'
  AND ap.delivery_method = 'homedelivery'
  AND (ap.preorder = FALSE OR ap.preorder IS NULL)
  AND (NOT ctg.is_duplicate OR ctg.is_duplicate IS NULL)
  AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
  AND sla.is_late = TRUE
  AND courier_dropoff_tasks.completed_with_vehicle_type IS NOT NULL

ORDER BY ap.time_delivered::TIMESTAMP DESC
