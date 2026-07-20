-- Country-wide TTLA context for the TTLA tab's "Country TTLA context" panel (the
-- panel above Venue TTLA & unassign). Returns per operations-area (city) TTLA
-- inputs for the WHOLE country over the tab's chosen period + order type, so the
-- router can compute the country TTLA, the selected city's share/impact on it, and
-- the gap vs the target.
--
-- SAME authoritative TTLA population as the tab's Orders/Venues/Couriers views
-- (INTERMEDIATE.f_purchases.time_to_last_accept_sec; status IN
-- ('delivered','refunded'); delivery_provider_type = 'relay'; non-null TTLA),
-- scoped by the shared {order_type_clause} (is_drive: Regular default / Drive) +
-- {date_window_clause} (rolling days / complete weeks / custom range). So the city
-- TTLA here reconciles with the Orders/Venues/Couriers panels for the same period
-- + order type (it is NOT product-line / preorder restricted like the Venue TTLA &
-- unassign panel).
--
-- Grouped by venue_operations_area (NOT the selected city) — the router sums all
-- rows to the country total and picks the selected city's row, so city sums
-- reconcile EXACTLY to the country total (every row carries one operations area).
-- TTLA = Σsec/Σcount is an order-weighted mean (COUNT/SUM ignore NULLs == AVG over
-- the same rows), matching the authoritative metric.
{ttla_cte_outer}SELECT
    COALESCE(fp.venue_operations_area, 'Unknown') AS city,
    COUNT({ttla_expr}) AS ttla_order_count,
    ROUND(SUM({ttla_expr}), 2) AS ttla_sec_sum
FROM INTERMEDIATE.f_purchases AS fp
{ttla_join}
WHERE fp.venue_country = '{country}'
  AND fp.status IN ('delivered', 'refunded')
  AND fp.delivery_provider_type = 'relay'
  AND {ttla_not_null}
  {order_type_clause}
  {date_window_clause}
  {delivery_counts_clause}
GROUP BY 1
ORDER BY ttla_order_count DESC
