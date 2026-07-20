-- Country-wide daily Average Delivery Time (ADT) inputs (drive orders excluded),
-- on the same INTERMEDIATE.f_purchases spine, WHERE clause and UTC confirmed_date
-- bucketing as country_daily_rates_total.sql, so ADT lines up with the Region
-- tab's other metrics.
--
-- ADT = order-weighted mean delivery time in MINUTES = SUM(delivery minutes) /
-- COUNT(qualifying delivery orders). We return the SUM (delivery_min_sum) and the
-- COUNT (delivery_order_count) per day rather than a precomputed average so the
-- frontend can aggregate an order-weighted mean across days, cities and countries
-- (Σ minutes / Σ orders) and never has to average daily %s.
--
-- The per-order delivery-time definition is IDENTICAL to the dashboard's existing
-- avg_delivery_time (country_hl_lateness_total.sql / country_perf_metrics.sql):
-- delivery_time_sec/60 for non-preorder homedelivery orders that were delivered by
-- a non-self provider within 5min..3h. Because delivery_min_sum /
-- delivery_order_count == AVG(delivery_time_sec/60 over those same rows), ADT
-- equals that existing metric exactly. delivery_order_count is the AVG's row-based
-- denominator (the count of qualifying order-rows the mean is taken over).
--
-- RECONCILIATION: this is the country total; country_adt_by_city.sql breaks the
-- same SUM/COUNT out by operations area, assigning each purchase a single city, so
-- summing the city minutes/orders reconciles EXACTLY to these totals.
SELECT
    TO_CHAR(TO_DATE(fp.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    COUNT(
        CASE WHEN fp.is_preorder = 'False'
              AND fp.delivery_method = 'homedelivery'
              AND fp.time_delivered_utc IS NOT NULL
              AND (fp.delivery_provider_type <> 'self' OR fp.delivery_provider_type IS NULL)
              AND fp.delivery_time_sec > 300
              AND fp.delivery_time_sec < 10800
             THEN fp.purchase_id
        END
    ) AS delivery_order_count,
    ROUND(SUM(
        CASE WHEN fp.is_preorder = 'False'
              AND fp.delivery_method = 'homedelivery'
              AND fp.time_delivered_utc IS NOT NULL
              AND (fp.delivery_provider_type <> 'self' OR fp.delivery_provider_type IS NULL)
              AND fp.delivery_time_sec > 300
              AND fp.delivery_time_sec < 10800
             THEN fp.delivery_time_sec / 60.0
             ELSE NULL
        END
    ), 2) AS delivery_min_sum
FROM INTERMEDIATE.f_purchases AS fp
WHERE fp.venue_country = '{country}'
  AND fp.status = 'delivered'
  AND (NOT fp.is_drive OR fp.is_drive IS NULL)
  AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
  AND fp.time_confirmed_utc < CURRENT_DATE()
GROUP BY 1
ORDER BY 1
