-- Retail-TTLA tab: per-CITY average TTLA (Task to Last Accept) split by venue
-- product line, for the "Retail TTLA venue analysis" tab. TTLA is the seconds
-- before the courier who ultimately completes pickup accepted the task; higher =
-- slower = worse. This is the SAME authoritative TTLA metric + spine the Region /
-- Country / TTLA-tab panels use (INTERMEDIATE.f_purchases.time_to_last_accept_sec,
-- status IN ('delivered','refunded'), delivery_provider_type = 'relay', UTC
-- confirmed-date window, per venue_country + venue_operations_area).
--
-- EXCLUSIONS for this panel: scheduled/preorders (is_preorder) and time-slot
-- orders (is_time_slot_order) are ALWAYS excluded. Relay Express is now controlled by
-- the TTLA tab's GLOBAL Order-type filter via {order_type_clause}: Regular =
-- is_drive=FALSE (the historical on-demand population), Drive = is_drive=TRUE
-- (segment benchmark / Super Express). product_line_category is the authoritative venue segment
-- ('Restaurant' / 'Retail store' / 'Other'); the router forms the combined city
-- average (all groups) + the Restaurant vs Retail store averages from these rows.
--
-- TTLA is an order-weighted MEAN in SECONDS, so we emit per group the order_count
-- (rows the mean is taken over) + ttla_sec_sum (Σ seconds); the router forms
-- avg = ttla_sec_sum / order_count. We also emit the per-group city UNASSIGN
-- totals (the denominators for the segment benchmark-style venue unassign contribution/share
-- metrics): unassigned_count = TOTAL unassigns (is_purchase_unassigned), plus the
-- COURIER-initiated + OPS-initiated breakdowns (these two overlap, so they do NOT
-- sum to the total — the total is the distinct union). DEDUP: f_purchases can hold
-- >1 row per purchase_id, so QUALIFY keeps exactly one row per purchase.
WITH fp_base AS (
    SELECT
        fp.purchase_id,
        fp.product_line_category AS product_line_category,
        CAST(fp.time_to_last_accept_sec AS DOUBLE PRECISION) AS ttla_sec,
        IFF(fp.is_purchase_unassigned, 1, 0) AS unassigned_total,
        IFF(fp.is_purchase_unassigned_by_courier, 1, 0) AS unassigned_courier,
        IFF(fp.is_purchase_unassigned_by_ops, 1, 0) AS unassigned_ops
    FROM INTERMEDIATE.f_purchases AS fp
    WHERE fp.venue_country = '{country}'
      AND fp.venue_operations_area = '{city}'
      AND fp.status IN ('delivered', 'refunded')
      AND fp.delivery_provider_type = 'relay'
      {order_type_clause}
      AND fp.is_preorder = FALSE
      AND fp.is_time_slot_order = FALSE
      AND fp.time_to_last_accept_sec IS NOT NULL
      {date_window_clause}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fp.purchase_id ORDER BY fp.time_confirmed_utc DESC) = 1
)
SELECT
    COALESCE(product_line_category, 'Unknown') AS product_line_category,
    COUNT(*) AS order_count,
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum,
    SUM(unassigned_total) AS unassigned_count,
    SUM(unassigned_courier) AS unassigned_courier,
    SUM(unassigned_ops) AS unassigned_ops
FROM fp_base
GROUP BY product_line_category
ORDER BY order_count DESC
