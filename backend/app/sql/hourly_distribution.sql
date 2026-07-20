WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
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
        END, ap.time_delivered::TIMESTAMP)) AS hour_of_day,
    COUNT(DISTINCT ap.id) AS total_orders,
    COUNT(DISTINCT CASE WHEN sla.is_late THEN ap.id END) AS late_orders,
    COUNT(DISTINCT CASE WHEN
        (ap.pre_estimate_high + 20) <
        (CASE WHEN ap.status IN ('delivered','refunded')
              THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                  - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
              ELSE NULL END)
        THEN ap.id END) AS late_orders_sla,
    ROUND(AVG(
        CASE WHEN ap.status IN ('delivered','refunded')
             THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                 - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
             ELSE NULL END
    ), 1) AS avg_completion_min

FROM staging.purchases AS ap
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id

WHERE ap.delivery_method = 'homedelivery'
  AND (ap.preorder = FALSE OR ap.preorder IS NULL)
  AND ap.delivery_provider = 'relay'
  AND (NOT ctg.is_duplicate OR ctg.is_duplicate IS NULL)
  AND v.city = '{city}'
  AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
  AND CASE WHEN ap.payment_method IN ('invoice','delivery_invoice','meal_benefit')
                OR ap.purchase_type = 'daas'
           THEN 'Corporate' ELSE 'Private'
      END = 'Private'
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()

GROUP BY 1, 2
ORDER BY 1, 2
