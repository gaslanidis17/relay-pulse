WITH purchase_sla AS (
    SELECT purchase_id, is_late, is_high_quality_delivery
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    ap.id                           AS purchase_id,
    ap.venue_name,
    ap.venue_id,
    ap.venue_lat,
    ap.venue_long,
    ap.USER_H3_HEXAGON_ID           AS dropoff_h3_index,
    ap.USER_H3_HEXAGON_CENTER_LAT   AS dropoff_h3_lat,
    ap.USER_H3_HEXAGON_CENTER_LON   AS dropoff_h3_lon,
    ap.status,
    ap.pre_estimate_avg,
    ap.pre_estimate_high,

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
    TO_CHAR(CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, ap.time_delivered::TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS')
        AS delivered_at,
    TO_CHAR(CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, ap.time_received::TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS')
        AS received_at,
    EXTRACT(HOUR FROM CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, ap.time_delivered::TIMESTAMP))
        AS delivered_hour,

    CASE WHEN ap.status IN ('delivered','refunded')
         THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
             - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
         ELSE NULL
    END AS completion_time_min,

    IFF(ap.preorder = FALSE, ap.pre_estimate_avg, NULL)
        - CASE WHEN ap.status IN ('delivered','refunded')
               THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                   - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
               ELSE NULL
          END AS pre_estimate_error_min,

    CASE WHEN (ap.pre_estimate_high + 20) <
              (CASE WHEN ap.status IN ('delivered','refunded')
                    THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                        - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
                    ELSE NULL END)
         THEN TRUE ELSE FALSE
    END AS is_sla_breach,

    sla.is_late AS is_sla_breach_official,

    -- Venue ready vs last pickup ETA (seconds, positive = venue late)
    TIMESTAMPDIFF(SECOND,
        ARRAY_SLICE(ap.pickup_eta_log, ARRAY_SIZE(ap.pickup_eta_log)-1, ARRAY_SIZE(ap.pickup_eta_log))[0]:eta::TIMESTAMP,
        ap.time_ready::TIMESTAMP
    ) AS ready_vs_pickup_eta_sec,

    CASE WHEN pdt.first_pickup_arrived_at::TIMESTAMP >
              ARRAY_SLICE(ap.pickup_eta_log, ARRAY_SIZE(ap.pickup_eta_log)-1, ARRAY_SIZE(ap.pickup_eta_log))[0]:eta::TIMESTAMP
         THEN TRUE ELSE FALSE
    END AS courier_arrived_after_eta,

    TIMESTAMPDIFF(SECOND,
        pdt.first_pickup_arrived_at::TIMESTAMP,
        pdt.first_pickup_completed_at::TIMESTAMP
    ) AS courier_wait_at_venue_sec,

    TIMESTAMPDIFF(SECOND,
        pdt.first_pickup_started_at::TIMESTAMP,
        pdt.COURIER_ARRIVED_50M_FROM_VENUE::TIMESTAMP
    ) / 60.0 AS pickup_duration_min,

    ROUND((EXTRACT(EPOCH FROM ap.pickup_eta_log[0]:eta::TIMESTAMP)
         - EXTRACT(EPOCH FROM ap.time_received::TIMESTAMP)) / 60)
        AS initial_pickup_eta_min,

    (pdt.courier_pickup_task_duration + pdt.courier_dropoff_task_duration)
        AS courier_task_total_min,

    CASE WHEN pdt.first_pickup_started_at::TIMESTAMP < ap.time_ready::TIMESTAMP
         THEN TRUE ELSE FALSE
    END AS courier_started_before_ready,

    COALESCE(bp."BUNDLED_PURCHASES_COUNT", 1) AS bundled_count,

    ctg."TIME_TO_LAST_ACCEPT" AS time_to_last_accept_sec,

    -- New columns for expanded flags
    ctg."DROPOFF_TASK_NAVIGATOR_DISTANCE"       AS dropoff_distance_m,
    ctg."SHOWN_TO_COURIERS_COUNT"               AS shown_to_couriers_count,
    ctg."TASK_ACCEPTED_COUNT"                   AS task_accepted_count,
    ctg."INITIAL_DELIVERY_ETA_ERROR_SECONDS"    AS eta_error_seconds,
    ctg."VEHICLE_TYPE"                          AS vehicle_type,
    pdt.RESTAURANT_TOTAL_TIME                   AS restaurant_total_time_min,
    pdt.COURIER_PICKUP_TIME_TO_VENUE            AS courier_travel_to_venue_min,
    COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE)      AS is_heavy_delivery,
    COALESCE(fcd.IS_LARGE_DELIVERY, FALSE)      AS is_large_delivery

FROM staging.purchases AS ap
LEFT JOIN public.venues                 AS v   ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN production.presentation.purchase_delivery_time_breakdowns AS pdt
    ON ap.id = pdt.purchase_id
LEFT JOIN "PRESENTATION"."BUNDLED_PURCHASES" AS bp
    ON ap.id = bp."PURCHASE_ID"
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id
LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id

WHERE ap.delivery_method = 'homedelivery'
  AND (ap.preorder = FALSE OR ap.preorder IS NULL)
  AND ap.delivery_provider = 'relay'
  AND (NOT ctg.is_duplicate OR ctg.is_duplicate IS NULL)
  AND v.city = '{city}'
  AND CASE
        WHEN ap.payment_method IN ('invoice','delivery_invoice','meal_benefit')
             OR ap.purchase_type = 'daas'
        THEN 'Corporate' ELSE 'Private'
      END = 'Private'
  AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
  AND (ap.pre_estimate_high + 20) <
      (CASE WHEN ap.status IN ('delivered','refunded')
            THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
            ELSE NULL END)

ORDER BY ap.time_delivered::TIMESTAMP DESC
