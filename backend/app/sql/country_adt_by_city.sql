-- Country daily Average Delivery Time (ADT) inputs BROKEN OUT BY CITY (operations
-- area), on the same INTERMEDIATE.f_purchases spine as country_adt_total.sql.
-- Identical WHERE clause + per-order delivery-time definition; the only addition
-- is the city dimension.
--
-- ADT is an order-weighted MEAN, so we emit the per-(day, city) SUM of delivery
-- minutes (delivery_min_sum) and the COUNT of qualifying delivery orders
-- (delivery_order_count); the frontend forms ADT = Σ minutes / Σ orders and
-- aggregates an order-weighted mean across cities/days. Lower ADT = faster.
--
-- RECONCILIATION: a small fraction of purchases have rows under more than one
-- venue_operations_area. We assign each purchase a SINGLE city via
-- MIN(venue_operations_area) OVER (PARTITION BY purchase_id) (MIN() OVER ignores
-- NULLs; COALESCE falls back to 'Unknown'), keeping ALL rows. Because every row of
-- a purchase gets that same assigned city, the per-city SUM/COUNT summed over all
-- cities reconciles EXACTLY to country_adt_total.sql (which sums/counts the same
-- rows without the city split). Do NOT inner-filter to the curated city list.
WITH fp_city AS (
    SELECT
        fp.purchase_id,
        fp.time_confirmed_utc,
        fp.is_preorder,
        fp.delivery_method,
        fp.time_delivered_utc,
        fp.delivery_provider_type,
        fp.delivery_time_sec,
        COALESCE(MIN(fp.venue_operations_area) OVER (PARTITION BY fp.purchase_id), 'Unknown') AS city
    FROM INTERMEDIATE.f_purchases AS fp
    WHERE fp.venue_country = '{country}'
      AND fp.status = 'delivered'
      AND (NOT fp.is_drive OR fp.is_drive IS NULL)
      AND fp.time_confirmed_utc >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND fp.time_confirmed_utc < CURRENT_DATE()
)
SELECT
    TO_CHAR(TO_DATE(fpc.time_confirmed_utc), 'YYYY-MM-DD') AS confirmed_date,
    fpc.city AS city,
    COUNT(
        CASE WHEN fpc.is_preorder = 'False'
              AND fpc.delivery_method = 'homedelivery'
              AND fpc.time_delivered_utc IS NOT NULL
              AND (fpc.delivery_provider_type <> 'self' OR fpc.delivery_provider_type IS NULL)
              AND fpc.delivery_time_sec > 300
              AND fpc.delivery_time_sec < 10800
             THEN fpc.purchase_id
        END
    ) AS delivery_order_count,
    ROUND(SUM(
        CASE WHEN fpc.is_preorder = 'False'
              AND fpc.delivery_method = 'homedelivery'
              AND fpc.time_delivered_utc IS NOT NULL
              AND (fpc.delivery_provider_type <> 'self' OR fpc.delivery_provider_type IS NULL)
              AND fpc.delivery_time_sec > 300
              AND fpc.delivery_time_sec < 10800
             THEN fpc.delivery_time_sec / 60.0
             ELSE NULL
        END
    ), 2) AS delivery_min_sum
FROM fp_city AS fpc
GROUP BY 1, 2
ORDER BY 1, 2
