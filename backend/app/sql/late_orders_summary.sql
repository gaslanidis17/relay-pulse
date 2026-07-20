WITH purchase_sla AS (
    SELECT purchase_id, is_late
    FROM intermediate.f_purchases_high_quality_deliveries
    WHERE is_sla_aligned_definition = TRUE
),
base AS (
    SELECT
        ap.id,
        ap.status,
        ap.pre_estimate_high,
        ap.pre_estimate_avg,
        ap.preorder,
        CASE WHEN ap.status IN ('delivered','refunded')
             THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                 - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
             ELSE NULL
        END AS completion_min,
        sla.is_late AS is_late_official,
        CASE WHEN (ap.pre_estimate_high + 20) <
                  (CASE WHEN ap.status IN ('delivered','refunded')
                        THEN (DATE_PART('epoch', ap.time_delivered::TIMESTAMP)
                            - DATE_PART('epoch', ap.time_received::TIMESTAMP)) / 60
                        ELSE NULL END)
             THEN TRUE ELSE FALSE
        END AS is_sla_breach,
        TO_CHAR(TO_DATE(
            CONVERT_TIMEZONE('UTC', CASE
                WHEN ap.timezone = 'Europe/Saratov'        THEN 'Etc/GMT-4'
                WHEN ap.timezone = 'Asia/Atyrau'           THEN 'Etc/GMT-5'
                WHEN ap.timezone = 'Asia/Qostanay'         THEN 'Etc/GMT-6'
                WHEN ap.timezone = 'Asia/Yangon'           THEN 'Asia/Rangoon'
                WHEN ap.timezone = 'Asia/Famagusta'        THEN 'Asia/Nicosia'
                WHEN ap.timezone = 'America/Nuuk'          THEN 'America/Godthab'
                WHEN ap.timezone = 'America/Punta_Arenas'  THEN 'America/Santiago'
                ELSE ap.timezone
            END, ap.time_delivered::TIMESTAMP)
        ), 'YYYY-MM-DD') AS delivered_date
    FROM staging.purchases AS ap
    LEFT JOIN public.venues AS v ON ap.venue_id = v.venue_id
    LEFT JOIN presentation.task_groups_enriched AS ctg ON ap.id = ctg.purchase_id
    LEFT JOIN purchase_sla AS sla ON ap.id = sla.purchase_id
    WHERE ap.delivery_method = 'homedelivery'
      AND (ap.preorder = FALSE OR ap.preorder IS NULL)
      AND ap.delivery_provider = 'relay'
      AND (NOT ctg.is_duplicate OR ctg.is_duplicate IS NULL)
      AND v.city = '{city}'
      AND ap.purchase_type NOT IN ('daas','subscription','giftcard','instore')
      AND CASE WHEN ap.payment_method IN ('invoice','delivery_invoice','meal_benefit')
                    OR ap.purchase_type = 'daas'
               THEN 'Corporate' ELSE 'Private'
          END = 'Private'
      AND ap.time_delivered::TIMESTAMP >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
      AND ap.time_delivered::TIMESTAMP < CURRENT_DATE()
)
SELECT
    COUNT(DISTINCT id) AS total_orders,
    COUNT(DISTINCT CASE WHEN is_sla_breach THEN id END) AS late_orders,
    COUNT(DISTINCT CASE WHEN is_late_official THEN id END) AS late_orders_official,
    ROUND(COUNT(DISTINCT CASE WHEN is_sla_breach THEN id END)::FLOAT
        / NULLIF(COUNT(DISTINCT id), 0) * 100, 2) AS late_pct,
    ROUND(AVG(CASE WHEN is_sla_breach THEN completion_min END), 1) AS avg_late_completion_min,
    ROUND(AVG(completion_min), 1) AS avg_completion_min,
    MIN(delivered_date) AS period_start,
    MAX(delivered_date) AS period_end
FROM base
