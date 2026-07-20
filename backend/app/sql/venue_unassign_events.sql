-- AI Venue Diagnostic — Pack 5 ENRICHMENT (v2): per-VENUE unassign EVENT detail
-- from INTERMEDIATE.F_COURIER_DELIVERY_UNASSIGNS (the modeled unassign-event list;
-- one row per courier delivery task, UNASSIGN_TYPE populated only when the task was
-- actually unassigned — NULL rows are completed deliveries, so we require
-- UNASSIGN_TYPE IS NOT NULL). This goes BEYOND the f_purchases unassign flags used
-- in Pack 1/5 (which count whether a purchase was unassigned at all): here we count
-- the number of unassign EVENTS (multiplicity), how many DISTINCT couriers dropped
-- the order, the Courier/Ops split at the event grain, and how long the courier held
-- the task before dropping it (wait_sec = started -> unassigned).
--
-- The population is pinned to the SAME on-demand TTLA set as retail_ttla_venues.sql
-- (same country/city/status/provider/segment/order-type/window + dedup) via the
-- `pop` CTE, so these events belong to exactly the venue orders the diagnostic scores.
-- One row per venue_id. Summed events_courier + events_ops == unassign_events.
WITH pop AS (
    SELECT
        fp.purchase_id AS purchase_id,
        ap.venue_id AS venue_id,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name
    FROM INTERMEDIATE.f_purchases AS fp
    LEFT JOIN staging.purchases AS ap ON ap.id = fp.purchase_id
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
),
ev AS (
    SELECT
        p.venue_id AS venue_id,
        p.venue_name AS venue_name,
        u.purchase_id AS purchase_id,
        u.courier_id AS courier_id,
        u.unassign_type AS unassign_type,
        DATEDIFF('second', u.time_delivery_started_utc, u.time_delivery_unassigned_utc) AS wait_sec
    FROM INTERMEDIATE.f_courier_delivery_unassigns AS u
    JOIN pop AS p ON p.purchase_id = u.purchase_id
    WHERE u.unassign_type IS NOT NULL
)
SELECT
    venue_id,
    MAX(venue_name) AS venue_name,
    COUNT(*) AS unassign_events,
    COUNT(DISTINCT purchase_id) AS purchases_unassigned,
    COUNT(DISTINCT courier_id) AS distinct_couriers,
    SUM(IFF(unassign_type = 'Courier', 1, 0)) AS events_courier,
    SUM(IFF(unassign_type = 'Ops', 1, 0)) AS events_ops,
    -- Hold time before dropping the task, clamped to a sane 0-2h band so a stray
    -- negative / multi-day outlier can't distort the mean (median is robust anyway).
    ROUND(AVG(IFF(wait_sec BETWEEN 0 AND 7200, wait_sec, NULL)), 1) AS avg_wait_sec,
    MEDIAN(IFF(wait_sec BETWEEN 0 AND 7200, wait_sec, NULL)) AS median_wait_sec
FROM ev
GROUP BY venue_id
ORDER BY unassign_events DESC
