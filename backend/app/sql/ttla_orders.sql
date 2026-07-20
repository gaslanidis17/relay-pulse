-- TTLA (Task to Last Accept) per-ORDER detail for the dedicated TTLA tab's
-- "Orders" view. TTLA is the seconds before the courier who ultimately completes
-- pickup accepted the task; higher = slower to accept = worse. This is the SAME
-- authoritative metric + filters the Region/Country TTLA panels use
-- (INTERMEDIATE.f_purchases.time_to_last_accept_sec, status IN
-- ('delivered','refunded'), delivery_provider_type = 'relay', UTC confirmed_date
-- window, per venue_country + venue_operations_area), only surfaced at order grain
-- with the venue name + courier enrichments the TTLA tab needs.
--
-- ENRICHMENT (documented, safe purchase_id joins — see SNOWFLAKE_LATENESS.md §1):
--   * staging.purchases (ap.id = fp.purchase_id) → venue_name / venue_id (the
--     f_purchases country spine only carries venue_operations_area = the city, not
--     the venue name), 1:1 on purchase id.
--   * intermediate.f_courier_deliveries_core → courier_id + IS_HEAVY/IS_LARGE.
--     A purchase can have >1 delivery row, so it is pre-aggregated to ONE row per
--     purchase (MIN(courier_id); heavy/large = MAX over the purchase's deliveries)
--     to avoid fanning out / double-counting TTLA.
--
-- DEDUP: f_purchases can hold >1 row per purchase_id (same pattern the by-city
-- files handle with MIN(...) OVER); we keep exactly one row per purchase via
-- QUALIFY ROW_NUMBER() so a purchase's TTLA is listed once. {size_filter_clause}
-- (empty for "all") optionally restricts to heavy / large orders via the fcd
-- flags. Ordered worst-first (highest TTLA) and capped at {row_limit} rows — this
-- is an inspection list of the slowest-to-accept orders, not the full set.
WITH fcd_agg AS (
    SELECT
        purchase_id,
        MIN(courier_id) AS courier_id,
        MAX(IFF(COALESCE(is_heavy_delivery, FALSE), 1, 0)) AS is_heavy,
        MAX(IFF(COALESCE(is_large_delivery, FALSE), 1, 0)) AS is_large,
        MIN(completed_with_vehicle_type) AS vehicle_type
    FROM intermediate.f_courier_deliveries_core
    GROUP BY purchase_id
){ttla_cte_inner},
fp_base AS (
    SELECT
        fp.purchase_id,
        TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
        TO_CHAR(fp.time_confirmed_utc, 'YYYY-MM-DD HH24:MI:SS') AS confirmed_at,
        fp.venue_operations_area AS city,
        fp.venue_country AS country,
        fp.status,
        {ttla_expr} AS ttla_sec,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name,
        ap.venue_id AS venue_id,
        fp.product_line_category AS product_line_category,
        fa.courier_id AS courier_id,
        COALESCE(fa.is_heavy, 0) AS is_heavy,
        COALESCE(fa.is_large, 0) AS is_large,
        -- Authoritative per-purchase delivery count (platform fulfillment metric).
        -- warehouse exposes as f_purchases.deliveries_count). >1 = the order had
        -- more than one courier delivery = a cloned/duplicated order. This is the
        -- source the user trusts (NOT COUNT(*) over f_courier_deliveries_core,
        -- which only sees completed deliveries and undercounts).
        COALESCE(fp.deliveries_count, 1) AS delivery_count,
        -- Prep-estimate error (minutes, signed): actual venue-ready time minus the
        -- venue's INITIAL pickup ETA (pickup_eta_log[0] = the venue's own first
        -- "order will be ready for pickup" estimate = its preparation-time promise).
        -- Positive = venue was ready LATER than promised (slow prep); negative =
        -- ready early. When time_ready is missing we FALL BACK to the pickup-completed
        -- timestamp (fp.time_first_pickup_completed_utc, same UTC basis) so the error
        -- is defined for orders with no explicit ready signal (~100% coverage). NULL
        -- only when the initial ETA and both ready sources are missing.
        ROUND(TIMESTAMPDIFF(SECOND, ap.pickup_eta_log[0]:eta::TIMESTAMP, COALESCE(ap.time_ready::TIMESTAMP, fp.time_first_pickup_completed_utc::TIMESTAMP)) / 60.0, 1) AS prep_error_min
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
      {min_ttla_clause}
      {vehicle_type_clause}
      {drill_clause}
      {inspect_venue_clause}
      {delivery_counts_clause}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fp.purchase_id ORDER BY fp.time_confirmed_utc DESC) = 1
)
SELECT
    purchase_id,
    confirmed_date,
    confirmed_at,
    city,
    country,
    status,
    venue_name,
    venue_id,
    product_line_category,
    courier_id,
    is_heavy,
    is_large,
    delivery_count,
    ROUND(ttla_sec, 1) AS ttla_sec,
    prep_error_min
FROM fp_base
ORDER BY ttla_sec DESC
LIMIT {row_limit}
