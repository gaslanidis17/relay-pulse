-- TTLA (Task to Last Accept) aggregated per VENUE for the TTLA tab's "Venues"
-- view. Same authoritative metric + filters + enrichment + dedup as
-- ttla_orders.sql (see that file for the full rationale); here we roll the
-- deduped per-purchase rows up to one row per venue.
--
-- TTLA is an order-weighted MEAN in SECONDS, so we emit the per-venue order_count
-- (rows the mean is taken over) and ttla_sec_sum (Σ seconds); the router forms
-- avg_ttla_sec = ttla_sec_sum / order_count. Ordered by volume desc; the frontend
-- re-sorts. {size_filter_clause} (empty for "all") optionally restricts to heavy /
-- large orders via the fcd flags.
WITH fcd_agg AS (
    SELECT
        purchase_id,
        MIN(courier_id) AS courier_id,
        MAX(IFF(COALESCE(is_heavy_delivery, FALSE), 1, 0)) AS is_heavy,
        MAX(IFF(COALESCE(is_large_delivery, FALSE), 1, 0)) AS is_large
    FROM intermediate.f_courier_deliveries_core
    GROUP BY purchase_id
){ttla_cte_inner},
fp_base AS (
    SELECT
        fp.purchase_id,
        {ttla_expr} AS ttla_sec,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name,
        ap.venue_id AS venue_id,
        fp.product_line_category AS product_line_category,
        COALESCE(fa.is_heavy, 0) AS is_heavy,
        COALESCE(fa.is_large, 0) AS is_large
    FROM INTERMEDIATE.f_purchases AS fp
    LEFT JOIN staging.purchases AS ap ON ap.id = fp.purchase_id
    LEFT JOIN fcd_agg AS fa ON fa.purchase_id = fp.purchase_id
    {ttla_join}
    WHERE fp.venue_country = '{country}'
      AND fp.venue_operations_area = '{city}'
      AND fp.status IN ('delivered', 'refunded')
      AND fp.delivery_provider_type = 'relay'
      AND {ttla_not_null}
      {order_type_clause}
      {date_window_clause}
      {size_filter_clause}
      {venue_type_clause}
      {retail_venue_clause}
      {delivery_counts_clause}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fp.purchase_id ORDER BY fp.time_confirmed_utc DESC) = 1
)
SELECT
    venue_name,
    venue_id,
    MAX(product_line_category) AS product_line_category,
    COUNT(*) AS order_count,
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum
FROM fp_base
GROUP BY venue_name, venue_id
{min_ttla_having}
ORDER BY order_count DESC
