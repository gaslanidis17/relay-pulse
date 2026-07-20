WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    ap.venue_id,
    ap.venue_name,
    MAX(v.product_line) AS venue_vertical,

    COUNT(DISTINCT ap.id) AS total_orders,

    COUNT(DISTINCT CASE WHEN sla.is_late THEN ap.id END) AS late_orders,

    COUNT(DISTINCT CASE
        WHEN ctg."TIME_TO_LAST_ACCEPT" / 60.0 >= {rotten_threshold_min}
        THEN ap.id END) AS rotten_orders,

    ROUND(AVG(ctg."TIME_TO_LAST_ACCEPT"), 1) AS avg_ttla_sec,

    ROUND(AVG(pdt.RESTAURANT_TOTAL_TIME), 1) AS avg_prep_time_min,

    ROUND(AVG(
        CASE WHEN ap.status IN ('delivered','refunded')
             THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                 - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
             ELSE NULL END
    ), 1) AS avg_completion_min,

    COUNT(DISTINCT CASE
        WHEN sla.is_late
         AND TIMESTAMPDIFF(SECOND,
            ARRAY_SLICE(ap.pickup_eta_log, ARRAY_SIZE(ap.pickup_eta_log)-1, ARRAY_SIZE(ap.pickup_eta_log))[0]:eta::TIMESTAMP,
            ap.time_ready::TIMESTAMP
        ) > {venue_late_threshold}
        THEN ap.id END) AS venue_late_count,

    COUNT(DISTINCT CASE
        WHEN sla.is_late
         AND TIMESTAMPDIFF(SECOND,
            ARRAY_SLICE(ap.pickup_eta_log, ARRAY_SIZE(ap.pickup_eta_log)-1, ARRAY_SIZE(ap.pickup_eta_log))[0]:eta::TIMESTAMP,
            ap.time_ready::TIMESTAMP
        ) < {venue_early_threshold}
        THEN ap.id END) AS venue_early_count

FROM staging.purchases AS ap
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN production.presentation.purchase_delivery_time_breakdowns AS pdt
    ON ap.id = pdt.purchase_id
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id
LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id

WHERE ap.delivery_method = 'homedelivery'
  {size_filter_clause}
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

GROUP BY ap.venue_id, ap.venue_name
HAVING COUNT(DISTINCT ap.id) >= 1
ORDER BY late_orders DESC
