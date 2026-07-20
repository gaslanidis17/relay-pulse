WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    ap.id AS purchase_id,
    ap.venue_name,
    ap.venue_id,
    ap.venue_lat,
    ap.venue_long,
    ap.USER_H3_HEXAGON_ID           AS dropoff_h3_index,
    ap.USER_H3_HEXAGON_CENTER_LAT   AS dropoff_h3_lat,
    ap.USER_H3_HEXAGON_CENTER_LON   AS dropoff_h3_lon,

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

    EXTRACT(HOUR FROM CONVERT_TIMEZONE('UTC', CASE
        WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
        WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
        WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
        WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
        WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
        WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
        WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
        ELSE ap.timezone
    END, ap.time_delivered::TIMESTAMP)) AS delivered_hour,

    ROUND(ctg."TIME_TO_LAST_ACCEPT" / 60.0, 1) AS time_to_accept_min,

    CASE WHEN ctg."TIME_TO_LAST_ACCEPT" / 60.0 >= {rotten_threshold_min}
         THEN TRUE ELSE FALSE
    END AS is_rotten,

    sla.is_late AS is_late_official,

    CASE WHEN ap.status IN ('delivered','refunded')
         THEN ROUND((DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
             - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60, 1)
         ELSE NULL
    END AS completion_time_min,

    ctg."SHOWN_TO_COURIERS_COUNT"           AS shown_to_couriers_count,
    ctg."TASK_ACCEPTED_COUNT"               AS task_accepted_count,
    ctg."ACCEPTANCE_RATE"                   AS acceptance_rate,
    ctg."VEHICLE_TYPE"                      AS vehicle_type,
    COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE)  AS is_heavy_delivery,
    COALESCE(fcd.IS_LARGE_DELIVERY, FALSE)  AS is_large_delivery

FROM staging.purchases AS ap
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN public.routemill_optimization_areas AS roa ON ctg.delivery_team = roa.id
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id
LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id

WHERE ap.delivery_provider = 'relay'
  AND ap.delivery_method = 'homedelivery'
  AND (ap.preorder = FALSE OR ap.preorder IS NULL)
  AND roa.city = '{city}'
  AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
  AND CASE
        WHEN ap.payment_method IN ('invoice','delivery_invoice','meal_benefit')
             OR ap.purchase_type = 'daas'
        THEN 'Corporate' ELSE 'Private'
      END = 'Private'
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
  AND ctg."TIME_TO_LAST_ACCEPT" / 60.0 >= {rotten_threshold_min}

ORDER BY time_to_accept_min DESC
