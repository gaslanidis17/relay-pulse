-- AI Venue Diagnostic — Pack 2 (time-based): per-VENUE, per LOCAL hour-of-day TTLA
-- + unassign aggregate. Same authoritative on-demand TTLA population + spine +
-- exclusions as retail_ttla_venues.sql (see that file), so a venue's rows here
-- reconcile to its retail_ttla_venues totals when summed over the 24 hours.
--
-- One row per (venue_id, hour_of_day 0-23). The router forms the order-weighted
-- TTLA (ttla_sec_sum / order_count) and the unassign rate per hour, then compares
-- each hour to the venue's own baseline (peak vs off-peak) and flags low-volume
-- hours so a 1-2 order hour is never read as a recurring problem.
--
-- HOUR: local hour of the order-confirmed timestamp. UTC time_confirmed_utc is
-- converted with the venue's staging timezone, remapping the IANA zones Snowflake
-- rejects (SNOWFLAKE_MASTER §8.1 / hourly_distribution.sql) inline verbatim.
-- DEDUP: QUALIFY keeps exactly one row per purchase_id before aggregating.
WITH fp_base AS (
    SELECT
        ap.venue_id AS venue_id,
        COALESCE(ap.venue_name, 'Unknown') AS venue_name,
        fp.product_line_category AS product_line_category,
        EXTRACT(HOUR FROM CONVERT_TIMEZONE('UTC', CASE
            WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
            WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
            WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
            WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
            WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
            WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
            WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
            ELSE ap.timezone
        END, fp.time_confirmed_utc::TIMESTAMP)) AS hour_of_day,
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
    hour_of_day,
    COUNT(*) AS order_count,
    ROUND(SUM(ttla_sec), 2) AS ttla_sec_sum,
    SUM(unassigned_total) AS unassigned_count,
    SUM(unassigned_courier) AS unassigned_courier,
    SUM(unassigned_ops) AS unassigned_ops
FROM fp_base
GROUP BY venue_id, hour_of_day
ORDER BY venue_id, hour_of_day
