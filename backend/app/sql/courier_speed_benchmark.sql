WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
),
travel AS (
    SELECT
        courier_dropoff_tasks_courier.vehicle_type AS vehicle_type,

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
        END AS dropoff_arrival_min

    FROM staging.purchases AS ap
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
      AND (NOT ctg.is_duplicate OR ctg.is_duplicate IS NULL)
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
      AND courier_dropoff_tasks_courier.vehicle_type IS NOT NULL
      AND ctg."PICKUP_TASK_NAVIGATOR_DISTANCE" IS NOT NULL
      AND ctg."DROPOFF_TASK_NAVIGATOR_DISTANCE" IS NOT NULL
)
SELECT
    vehicle_type,
    COUNT(*) AS order_count,

    ROUND(AVG(
        CASE WHEN pickup_arrival_min > 0 AND dropoff_arrival_min > 0
             AND pickup_distance_m + dropoff_distance_m > 100
             THEN (pickup_distance_m + dropoff_distance_m) / 1000.0
                  / ((pickup_arrival_min + dropoff_arrival_min) / 60.0)
             ELSE NULL
        END
    ), 1) AS avg_speed_kmh,

    ROUND(MEDIAN(
        CASE WHEN pickup_arrival_min > 0 AND dropoff_arrival_min > 0
             AND pickup_distance_m + dropoff_distance_m > 100
             THEN (pickup_distance_m + dropoff_distance_m) / 1000.0
                  / ((pickup_arrival_min + dropoff_arrival_min) / 60.0)
             ELSE NULL
        END
    ), 1) AS median_speed_kmh,

    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY
        CASE WHEN pickup_arrival_min > 0 AND dropoff_arrival_min > 0
             AND pickup_distance_m + dropoff_distance_m > 100
             THEN (pickup_distance_m + dropoff_distance_m) / 1000.0
                  / ((pickup_arrival_min + dropoff_arrival_min) / 60.0)
             ELSE NULL
        END
    ), 1) AS p25_speed_kmh,

    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY
        CASE WHEN pickup_arrival_min > 0 AND dropoff_arrival_min > 0
             AND pickup_distance_m + dropoff_distance_m > 100
             THEN (pickup_distance_m + dropoff_distance_m) / 1000.0
                  / ((pickup_arrival_min + dropoff_arrival_min) / 60.0)
             ELSE NULL
        END
    ), 1) AS p75_speed_kmh,

    ROUND(AVG(pickup_arrival_min), 1) AS avg_pickup_min,
    ROUND(AVG(dropoff_arrival_min), 1) AS avg_dropoff_min,
    ROUND(AVG(pickup_distance_m), 0) AS avg_pickup_distance_m,
    ROUND(AVG(dropoff_distance_m), 0) AS avg_dropoff_distance_m

FROM travel
WHERE pickup_arrival_min IS NOT NULL
  AND dropoff_arrival_min IS NOT NULL
  AND pickup_arrival_min > 0
  AND dropoff_arrival_min > 0

GROUP BY vehicle_type
ORDER BY order_count DESC
