-- Per-venue contribution of heavy / large orders (and how many of them were
-- cloned) for the Clone Rate tab "Top Venues" panel. No server-side size
-- filter: the full breakdown is returned so the frontend can switch between
-- heavy|large / heavy / large instantly and always show total orders.
--
-- "Cloned" = a purchase that has a duplicate task group (ctg.is_duplicate).
-- Heavy / large = fcd.IS_HEAVY_DELIVERY / IS_LARGE_DELIVERY.
WITH per_purchase AS (
    SELECT
        ap.id AS purchase_id,
        ap.venue_id,
        MAX(ap.venue_name) AS venue_name,
        MAX(v.product_line) AS venue_vertical,
        MAX(CASE WHEN COALESCE(fcd.IS_HEAVY_DELIVERY, FALSE) THEN 1 ELSE 0 END) AS is_heavy,
        MAX(CASE WHEN COALESCE(fcd.IS_LARGE_DELIVERY, FALSE) THEN 1 ELSE 0 END) AS is_large,
        MAX(CASE WHEN ctg.is_duplicate = TRUE THEN 1 ELSE 0 END) AS is_cloned,
        AVG(ctg."TIME_TO_LAST_ACCEPT") AS ttla_sec
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
    LEFT JOIN intermediate.f_courier_deliveries_core AS fcd ON ap.id = fcd.purchase_id
    WHERE v.city = '{city}'
      AND ap.delivery_method = 'homedelivery'
      AND ap.delivery_provider = 'relay'
      AND ap.time_delivered::TIMESTAMP >= '{date_from}'::DATE
      AND ap.time_delivered::TIMESTAMP < DATEADD('day', 1, '{date_to}'::DATE)
    GROUP BY ap.id, ap.venue_id
)
SELECT
    venue_id,
    MAX(venue_name) AS venue_name,
    MAX(venue_vertical) AS venue_vertical,
    COUNT(DISTINCT purchase_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN is_heavy = 1 THEN purchase_id END) AS heavy_orders,
    COUNT(DISTINCT CASE WHEN is_large = 1 THEN purchase_id END) AS large_orders,
    COUNT(DISTINCT CASE WHEN is_heavy = 1 OR is_large = 1 THEN purchase_id END) AS hl_orders,
    COUNT(DISTINCT CASE WHEN is_cloned = 1 AND is_heavy = 1 THEN purchase_id END) AS cloned_heavy,
    COUNT(DISTINCT CASE WHEN is_cloned = 1 AND is_large = 1 THEN purchase_id END) AS cloned_large,
    COUNT(DISTINCT CASE WHEN is_cloned = 1 AND (is_heavy = 1 OR is_large = 1) THEN purchase_id END) AS cloned_hl,
    ROUND(AVG(ttla_sec), 0) AS avg_ttla_sec
FROM per_purchase
GROUP BY venue_id
HAVING COUNT(DISTINCT CASE WHEN is_heavy = 1 OR is_large = 1 THEN purchase_id END) >= 1
ORDER BY hl_orders DESC
LIMIT 500
