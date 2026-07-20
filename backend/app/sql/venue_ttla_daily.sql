-- AI Venue Diagnostic — Pack 3 (time-based trend): per-VENUE, per LOCAL day TTLA +
-- unassign aggregate. Identical population + spine + exclusions + dedup to
-- venue_ttla_hourly.sql (and retail_ttla_venues.sql), grouped by local calendar
-- date instead of hour, so a venue's daily rows reconcile to its retail_ttla
-- totals when summed over the window.
--
-- The router uses this to separate a one-off SPIKE (a few bad days) from a
-- RECURRING problem (persistently elevated), and to describe the TTLA / unassign
-- trend over the window. DATE = local date of order confirmation via the same
-- SNOWFLAKE_MASTER §8.1 IANA remap used everywhere else.
WITH fp_base AS (
    SELECT
        ap.venue_id AS venue_id,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name,
        fp.product_line_category AS product_line_category,
        TO_CHAR(TO_DATE(CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, fp.time_confirmed_utc::TIMESTAMP)), 'YYYY-MM-DD') AS local_date,
        CAST(fp.time_to_last_accept_sec AS DOUBLE PRECISION) AS ttla_sec,
        IFF(fp.is_purchase_unassigned, 1, 0) AS unassigned_total,
        IFF(fp.is_purchase_unassigned_by_courier, 1, 0) AS unassigned_courier,
        IFF(fp.is_purchase_unassigned_by_ops, 1, 0) AS unassigned_ops
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
)
SELECT
    venue_id,
    MAX(venue_name) AS venue_name,
    MAX(product_line_category) AS product_line_category,
    local_date,
    COUNT(*) AS order_count,
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum,
    SUM(unassigned_total) AS unassigned_count,
    SUM(unassigned_courier) AS unassigned_courier,
    SUM(unassigned_ops) AS unassigned_ops
FROM fp_base
GROUP BY venue_id, local_date
ORDER BY venue_id, local_date
