-- Venue TTLA & unassign panel: per-VENUE TTLA + unassign aggregate for the venue
-- analysis + map (the former "Retail TTLA" overview, now covering BOTH segments so
-- the frontend can toggle Restaurant vs Retail store). Same authoritative TTLA
-- metric + spine + exclusions as retail_ttla_city_summary.sql (see that file),
-- restricted to the two ranked segments (product_line_category IN
-- ('Restaurant','Retail store')). One row per (segment, venue), enriched with the
-- venue name + coordinates so the frontend can rank the worst venues and map them.
--
-- ENRICHMENT (documented, safe purchase_id join — see SNOWFLAKE_LATENESS.md §1):
--   * staging.purchases (ap.id = fp.purchase_id) → venue_name / venue_id /
--     venue_lat / venue_long (the f_purchases country spine only carries
--     venue_operations_area = the city, not the venue name/coords), 1:1 on
--     purchase id.
--
-- TTLA is an order-weighted MEAN in SECONDS. Per venue we emit order_count +
-- ttla_sec_sum so the router forms avg = ttla_sec_sum / order_count and the
-- excess-seconds TTLA "impact" = order_count * (venue_avg - group_city_avg). We
-- also emit the unassign drivers the ranking table shows: unassigned_count (TOTAL,
-- is_purchase_unassigned) plus the COURIER- and OPS-initiated breakdowns (these two
-- overlap, so they do NOT sum to the total), and Σ/count of venue prep time +
-- pickup service time (the router forms order-weighted averages over the non-null
-- count). product_line_category is carried through so the router can group by
-- segment with the correct per-group city denominators.
-- DEDUP: QUALIFY keeps exactly one row per purchase_id before aggregating.
WITH fp_base AS (
    SELECT
        fp.purchase_id,
        fp.product_line_category AS product_line_category,
        CAST(fp.time_to_last_accept_sec AS DOUBLE PRECISION) AS ttla_sec,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name,
        ap.venue_id AS venue_id,
        ap.venue_lat AS venue_lat,
        ap.venue_long AS venue_long,
        -- Venue sub-type (grocery / pharmacy / alcohol / pet / etc.) from the venue
        -- dimension, and the attached account manager (resolved name; blank when the
        -- venue has none, e.g. owned Hub stores). Both keyed by venue_id (1:1), so
        -- MAX(...) in the aggregate just carries the constant venue attribute.
        vn.product_line AS venue_type,
        dv.account_manager_name AS account_manager,
        IFF(fp.is_purchase_unassigned, 1, 0) AS unassigned_total,
        IFF(fp.is_purchase_unassigned_by_courier, 1, 0) AS unassigned_courier,
        IFF(fp.is_purchase_unassigned_by_ops, 1, 0) AS unassigned_ops,
        CAST(fp.venue_prep_time_sec AS DOUBLE PRECISION) AS prep_sec,
        CAST(fp.pickup_service_time_sec AS DOUBLE PRECISION) AS pickup_sec,
        -- Prep-estimate error (seconds, signed): actual venue-ready time minus the
        -- venue's INITIAL pickup ETA (pickup_eta_log[0] = the venue's own first
        -- "ready for pickup" estimate = its preparation-time promise). Positive =
        -- ready LATER than promised. When time_ready is missing we FALL BACK to the
        -- pickup-completed timestamp (fp.time_first_pickup_completed_utc, same UTC
        -- basis) so ~all orders are covered. The router order-weights Σ/count into min.
        CAST(TIMESTAMPDIFF(SECOND, ap.pickup_eta_log[0]:eta::TIMESTAMP, COALESCE(ap.time_ready::TIMESTAMP, fp.time_first_pickup_completed_utc::TIMESTAMP)) AS DOUBLE PRECISION) AS prep_err_sec
    FROM INTERMEDIATE.f_purchases AS fp
    LEFT JOIN staging.purchases AS ap ON ap.id = fp.purchase_id
    LEFT JOIN public.venues AS vn ON vn.venue_id = ap.venue_id
    LEFT JOIN INTERMEDIATE.d_venues AS dv ON dv.venue_id = ap.venue_id
    WHERE fp.venue_country = '{country}'
      AND fp.venue_operations_area = '{city}'
      AND fp.status IN ('delivered', 'refunded')
      AND fp.delivery_provider_type = 'relay'
      AND fp.product_line_category IN ('Restaurant', 'Retail store')
      {order_type_clause}
      AND fp.is_preorder = FALSE
      AND fp.is_time_slot_order = FALSE
      AND fp.time_to_last_accept_sec IS NOT NULL
      {date_window_clause}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fp.purchase_id ORDER BY fp.time_confirmed_utc DESC) = 1
)
SELECT
    product_line_category,
    venue_name,
    venue_id,
    MAX(venue_lat) AS venue_lat,
    MAX(venue_long) AS venue_long,
    MAX(venue_type) AS venue_type,
    MAX(account_manager) AS account_manager,
    COUNT(*) AS order_count,
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum,
    SUM(unassigned_total) AS unassigned_count,
    SUM(unassigned_courier) AS unassigned_courier,
    SUM(unassigned_ops) AS unassigned_ops,
    ROUND(SUM(prep_sec), 2) AS prep_sec_sum,
    COUNT(prep_sec) AS prep_count,
    ROUND(SUM(pickup_sec), 2) AS pickup_sec_sum,
    COUNT(pickup_sec) AS pickup_count,
    ROUND(SUM(prep_err_sec), 2) AS prep_err_sec_sum,
    COUNT(prep_err_sec) AS prep_err_count
FROM fp_base
GROUP BY product_line_category, venue_name, venue_id
ORDER BY order_count DESC
