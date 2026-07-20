-- AI Venue Diagnostic — Pack 4 v2 (raw courier conversation text, PII-laden):
-- representative COURIER message bodies for ONE venue's pickup/reassign support
-- conversations, for a 2nd, PII-SCRUBBING LLM pass (never rendered raw / never
-- cached in an AI result). This is a DEEP, per-venue query (keyed by venue_id in
-- the cache suffix), run only in the background job when a Snowflake session is
-- live — it is NOT part of the city-wide nightly warm because the bodies are
-- personal data + Kazakh/Russian free text.
--
-- Linkage mirrors venue_courier_conversations.sql (Pack 4): the venue's on-demand
-- purchases -> INTERMEDIATE.F_SUPPORT_CONVERSATIONS (courier, CP + PU/R) gives the
-- conversation ids, which match STAGING.CONVERSE_MESSAGES.CONVERSATION_ID 1:1
-- (verified). We keep only the courier's OWN human messages (FROM_TYPE='contact',
-- TYPE='regular', not deleted), truncate each to 240 chars, and cap the total rows
-- so the payload + LLM input stay bounded. supportLayerFlowPath (the in-app path
-- the courier took to reach support) comes from STAGING.CONVERSE_CONVERSATIONS.
WITH vp AS (
    SELECT fp.purchase_id AS purchase_id
    FROM INTERMEDIATE.f_purchases AS fp
    LEFT JOIN staging.purchases AS ap ON ap.id = fp.purchase_id
    WHERE fp.venue_country = '{country}'
      AND fp.venue_operations_area = '{city}'
      AND ap.venue_id = '{venue_id}'
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
cc AS (
    SELECT DISTINCT
        c.CONVERSATION_ID AS conversation_id,
        t.GLOBAL_TAG_LVL2 AS tag_lvl2,
        t.GLOBAL_TAG_LVL3 AS tag_lvl3
    FROM INTERMEDIATE.F_SUPPORT_CONVERSATIONS AS c
    JOIN INTERMEDIATE.D_CONVERSATION_TAGS AS t
      ON t.CONVERSATION_ID = c.CONVERSATION_ID AND t.SOURCE = c.SOURCE
    JOIN vp ON vp.purchase_id = c.PURCHASE_ID
    WHERE c.SOURCE_APP = 'courier'
      AND t.GLOBAL_TAG_LVL1 = 'CP'
      AND t.GLOBAL_TAG_LVL2 IN ('PU', 'R')
)
SELECT
    cc.tag_lvl2,
    cc.tag_lvl3,
    LEFT(m.BODY, 240) AS body,
    m.CREATED_AT AS created_at,
    ARRAY_TO_STRING(conv.METADATA:supportLayerFlowPath, ' > ') AS flow_path
FROM cc
JOIN staging.CONVERSE_MESSAGES AS m ON m.CONVERSATION_ID = cc.conversation_id
LEFT JOIN staging.CONVERSE_CONVERSATIONS AS conv ON conv.ID = cc.conversation_id
WHERE m.FROM_TYPE = 'contact'
  AND m.TYPE = 'regular'
  AND m.BODY IS NOT NULL
  AND LENGTH(TRIM(m.BODY)) > 1
  AND COALESCE(m.DELETED, FALSE) = FALSE
ORDER BY m.CREATED_AT DESC
LIMIT 60
