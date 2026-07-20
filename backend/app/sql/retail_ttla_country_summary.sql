-- Venue TTLA & unassign panel: COUNTRY-wide (all cities) per-segment TTLA totals.
-- Identical population + exclusions to retail_ttla_city_summary.sql (same
-- authoritative on-demand TTLA set: status IN ('delivered','refunded'),
-- delivery_provider_type='relay', {order_type_clause}, is_preorder=FALSE,
-- is_time_slot_order=FALSE, non-null TTLA) but WITHOUT the venue_operations_area
-- (city) filter — so it rolls the whole country up per product_line_category.
--
-- Purpose: the "selected-venues what-if" needs a country denominator in the SAME
-- population as the venue list. A city venue's excess TTLA-seconds are part of BOTH
-- the city and the country segment totals, so subtracting the same excess from
-- these country totals gives the reconciling country segment TTLA if those venues
-- were fixed to (at least) the segment average.
--
-- TTLA is an order-weighted MEAN in SECONDS: per segment we emit order_count +
-- ttla_sec_sum, and the router forms avg = ttla_sec_sum / order_count. DEDUP:
-- QUALIFY keeps one row per purchase_id.
WITH fp_base AS (
    SELECT
        fp.purchase_id,
        fp.product_line_category AS product_line_category,
        CAST(fp.time_to_last_accept_sec AS DOUBLE PRECISION) AS ttla_sec
    FROM INTERMEDIATE.f_purchases AS fp
    WHERE fp.venue_country = '{country}'
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
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum
FROM fp_base
GROUP BY product_line_category
ORDER BY order_count DESC
