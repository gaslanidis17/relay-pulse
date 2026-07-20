-- AI Venue Diagnostic — Pack 6 (location / accessibility): one row per venue with
-- the merchant/venue attributes that explain pickup-access friction, from the
-- venue dimension INTERMEDIATE.D_VENUES (one live row per venue).
--
-- These attributes are date- and order-type INDEPENDENT (they describe the venue,
-- not the window), but the file is keyed by city like the other venue packs so the
-- diagnostic warms/reads them together. Filter is VENUE_CITY = '{city}' where
-- '{city}' is the WAREHOUSE operations-area value (the Astana->Nur-Sultan alias is
-- applied by the caller), which D_VENUES.VENUE_CITY matches verbatim.
--
-- has_opening_times / has_special_opening_times are presence flags on the VARIANT
-- schedule columns (the raw schedules are large + only needed as a signal that
-- hours / temporary closures exist). venue_courier_notes is the merchant's pickup
-- instructions (entrance / floor / parking / access) — the richest accessibility
-- signal, corroborated downstream by the Pack 4 Cantfindvenue / Venueclosed tags.
--
-- v2 (Phase 7) opening-hours correlation: rather than ship the large raw schedule
-- VARIANTs, we PARSE OPENING_TIMES here into a compact operating envelope
-- (open_hour = earliest daily open, close_hour = latest daily close, in the venue's
-- LOCAL hour) via a LATERAL FLATTEN over the per-weekday open/close arrays, plus a
-- count of SPECIAL_OPENING_TIMES entries (temporary-hours / closure overrides). The
-- router correlates the venue's worst-TTLA hours (Pack 2) against this envelope to
-- flag near-close or out-of-hours pickup friction.
WITH hours AS (
    SELECT
        dv.venue_id AS venue_id,
        MIN(CASE WHEN f.value:type::string = 'open'
                 THEN HOUR(TO_TIMESTAMP_NTZ(f.value:value::string)) END) AS open_hour,
        MAX(CASE WHEN f.value:type::string = 'close'
                 THEN HOUR(TO_TIMESTAMP_NTZ(f.value:value::string)) END) AS close_hour
    FROM INTERMEDIATE.d_venues AS dv,
         LATERAL FLATTEN(input => dv.opening_times) AS day,
         LATERAL FLATTEN(input => day.value) AS f
    WHERE dv.venue_country = '{country}'
      AND dv.venue_city = '{city}'
      AND dv.is_deleted = FALSE
      AND dv.opening_times IS NOT NULL
    GROUP BY dv.venue_id
)
SELECT
    dv.venue_id AS venue_id,
    dv.venue_name AS venue_name,
    dv.venue_city AS venue_city,
    dv.venue_address AS venue_address,
    dv.venue_postcode AS venue_postcode,
    dv.venue_type AS venue_type,
    dv.product_line_category AS product_line_category,
    dv.product_line_hierarchy_1 AS product_line_1,
    dv.product_line_hierarchy_2 AS product_line_2,
    dv.product_line_hierarchy_3 AS product_line_3,
    dv.retail_business_segment AS retail_business_segment,
    dv.merchant_type AS merchant_type,
    dv.is_hub_store AS is_hub_store,
    dv.is_eatin AS is_eatin,
    dv.is_takeaway AS is_takeaway,
    dv.franchise_name AS franchise_name,
    dv.brand_name AS brand_name,
    dv.venue_courier_notes AS venue_courier_notes,
    IFF(dv.opening_times IS NOT NULL, TRUE, FALSE) AS has_opening_times,
    IFF(dv.special_opening_times IS NOT NULL, TRUE, FALSE) AS has_special_opening_times,
    h.open_hour AS open_hour,
    h.close_hour AS close_hour,
    ARRAY_SIZE(dv.special_opening_times) AS special_opening_count,
    dv.venue_location_hex_8_string AS venue_hex8,
    dv.avg_uptime_l4w_min AS avg_uptime_l4w_min,
    dv.venue_location_latitude AS venue_lat,
    dv.venue_location_longitude AS venue_long,
    dv.account_manager_name AS account_manager
FROM INTERMEDIATE.d_venues AS dv
LEFT JOIN hours AS h ON h.venue_id = dv.venue_id
WHERE dv.venue_country = '{country}'
  AND dv.venue_city = '{city}'
  AND dv.is_deleted = FALSE
ORDER BY dv.venue_name
