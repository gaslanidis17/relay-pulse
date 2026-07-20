-- AI Venue Diagnostic — Pack 4 (courier experience): per-VENUE COURIER support
-- conversation themes, linked to the venue's on-demand orders in the window.
--
-- Canonical source (SNOWFLAKE_MASTER §9): INTERMEDIATE.F_SUPPORT_CONVERSATIONS
-- JOIN INTERMEDIATE.D_CONVERSATION_TAGS ON (CONVERSATION_ID, SOURCE) — the
-- master feed (NOT F_CONVERSE_CONVERSATIONS). We keep only COURIER-app
-- conversations (SOURCE_APP='courier') tagged on the Courier-Platform pickup /
-- reassign branches (GLOBAL_TAG_LVL1='CP' AND GLOBAL_TAG_LVL2 IN ('PU','R')) —
-- the pickup-experience + unassign-reason themes this feature explains.
--
-- Linkage: c.PURCHASE_ID -> the SAME windowed on-demand purchase set the venue
-- TTLA/hourly/daily packs use (venue_purchases CTE below reuses retail_ttla's
-- population + spine + exclusions), so themes are scoped to exactly the orders the
-- diagnostic is about and attributed to the correct venue.
--
-- DEDUP is critical: a conversation carries multiple tags and a purchase can have
-- multiple conversations, so every measure is COUNT(DISTINCT ...). Emits one row
-- per (venue_id, tag_lvl2, tag_lvl3) with conversation + touched-order counts and
-- first/last-seen so the router can rank themes and compute a per-venue
-- conversations-per-order share against its order volume.
WITH venue_purchases AS (
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
courier_convos AS (
    SELECT
        c.PURCHASE_ID AS purchase_id,
        c.CONVERSATION_ID AS conversation_id,
        t.GLOBAL_TAG_LVL2 AS tag_lvl2,
        t.GLOBAL_TAG_LVL3 AS tag_lvl3,
        c.TIME_CREATED_UTC AS created_utc
    FROM INTERMEDIATE.F_SUPPORT_CONVERSATIONS AS c
    JOIN INTERMEDIATE.D_CONVERSATION_TAGS AS t
      ON t.CONVERSATION_ID = c.CONVERSATION_ID AND t.SOURCE = c.SOURCE
    WHERE c.SOURCE_APP = 'courier'
      AND c.PURCHASE_ID IS NOT NULL
      AND c.CONVERSATION_COUNTRY = '{country}'
      AND t.GLOBAL_TAG_LVL1 = 'CP'
      AND t.GLOBAL_TAG_LVL2 IN ('PU', 'R')
)
SELECT
    vp.venue_id,
    MAX(vp.venue_name) AS venue_name,
    cc.tag_lvl2,
    cc.tag_lvl3,
    COUNT(DISTINCT cc.conversation_id) AS conversation_count,
    COUNT(DISTINCT cc.purchase_id) AS order_count,
    MIN(cc.created_utc) AS first_seen_utc,
    MAX(cc.created_utc) AS last_seen_utc
FROM venue_purchases AS vp
JOIN courier_convos AS cc ON cc.purchase_id = vp.purchase_id
GROUP BY vp.venue_id, cc.tag_lvl2, cc.tag_lvl3
ORDER BY vp.venue_id, conversation_count DESC
