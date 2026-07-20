WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
)
SELECT
    ap.venue_name,
    ap.venue_lat,
    ap.venue_long,
    COUNT(DISTINCT ap.id) AS total_orders,
    COUNT(DISTINCT CASE WHEN sla.is_late THEN ap.id END) AS late_orders,
    ROUND(COUNT(DISTINCT CASE WHEN sla.is_late THEN ap.id END)::FLOAT
        / NULLIF(COUNT(DISTINCT ap.id), 0) * 100, 2) AS lateness_rate,
    ROUND(AVG(
        CASE WHEN ap.status IN ('delivered','refunded') AND ap.preorder = FALSE
             THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                 - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
             ELSE NULL END
    ), 1) AS avg_completion_min,
    AVG(ctg."DROPOFF_TASK_NAVIGATOR_DISTANCE") AS avg_dropoff_distance

FROM staging.purchases AS ap
LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
LEFT JOIN public.routemill_tasks AS cdt
    ON ctg.id = cdt.task_group_id AND cdt.pickup_task = FALSE
LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id

WHERE v.city = '{city}'
  AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
  AND (ap.preorder = FALSE OR ap.preorder IS NULL)
  AND ap.time_slot_start IS NULL
  AND ap.delivery_method = 'homedelivery'
  AND ap.delivery_provider = 'relay'
  AND CASE
        WHEN ap.payment_method IN ('invoice','delivery_invoice','meal_benefit')
             OR ap.purchase_type = 'daas'
        THEN 'Corporate' ELSE 'Private'
      END = 'Private'
  AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()

GROUP BY 1, 2, 3
HAVING COUNT(cdt.id) >= 1
ORDER BY late_orders DESC
FETCH NEXT 5000 ROWS ONLY
