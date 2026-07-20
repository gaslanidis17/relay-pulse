"""Shared SQL clause + cache-suffix builders for the TTLA tab's GLOBAL filters.

The TTLA tab drives all of its panels (Retail overview, Orders, Venues,
Couriers) from ONE global filter set: Country, City, Period and Order type.
Country/City map onto the ``f_purchases`` spine the way each router already
handles them; this module centralizes the two dimensions that must format
IDENTICALLY across both routers (``ttla_orders`` + ``retail_ttla``) so a panel's
read and the admin warm never drift:

  * PERIOD -> ``date_window_clause`` on ``fp.time_confirmed_utc``. Three mutually
    exclusive modes (highest precedence first): a custom ``[from, to]`` day range,
    the last N COMPLETE ISO weeks (Mon 00:00 -> the most recent Sunday 24:00, the
    current partial week excluded), or the rolling last N complete days. Every
    mode excludes the current partial day like the rest of the app.
  * ORDER TYPE -> ``order_type_clause`` on ``fp.is_drive``: ``regular`` =
    is_drive=FALSE (Restaurant + Retail), ``drive`` = is_drive=TRUE (Relay Express /
    segment benchmark / Super Express). Regular is the default and, so it keeps reading the
    pre-existing default-warmed cache files, contributes NO cache suffix.

Complete-weeks anchoring uses ``DAYOFWEEKISO`` explicitly (Monday = 1) so it is
deterministic regardless of the Snowflake ``WEEK_START`` session parameter.
"""

from __future__ import annotations

from typing import Optional

# Order-type UI slugs <-> is_drive.
ORDER_TYPE_REGULAR = "regular"
ORDER_TYPE_DRIVE = "drive"
ORDER_TYPES = {ORDER_TYPE_REGULAR, ORDER_TYPE_DRIVE}

# Monday 00:00 of the CURRENT ISO week (the exclusive upper bound of the
# last-complete-weeks window).
_ISO_WEEK_START = "DATEADD('day', -(DAYOFWEEKISO(CURRENT_DATE()) - 1), CURRENT_DATE())"


def _sql_str(v) -> str:
    """Escape a single-quoted SQL literal (values come from server-mapped enums /
    numeric inputs, but be defensive)."""
    return str(v).replace("'", "''")


def norm_order_type(order_type: Optional[str]) -> str:
    """Normalize the order-type slug; anything unknown falls back to ``regular``
    (the historical default population minus Drive)."""
    return order_type if order_type in ORDER_TYPES else ORDER_TYPE_REGULAR


def date_window_clause(
    lookback_days: int,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    complete_weeks: Optional[int] = None,
) -> str:
    """The confirmed-UTC window clause. Precedence: custom range > complete weeks >
    rolling days. All bounds exclude the current partial day."""
    if date_from and date_to:
        return (
            f"AND fp.time_confirmed_utc >= '{_sql_str(date_from)}' "
            f"AND fp.time_confirmed_utc < DATEADD('day', 1, '{_sql_str(date_to)}')"
        )
    if complete_weeks:
        n = int(complete_weeks)
        return (
            f"AND fp.time_confirmed_utc >= DATEADD('week', -{n}, {_ISO_WEEK_START}) "
            f"AND fp.time_confirmed_utc < {_ISO_WEEK_START}"
        )
    return (
        f"AND fp.time_confirmed_utc >= DATEADD('day', -{int(lookback_days)}, CURRENT_DATE()) "
        f"AND fp.time_confirmed_utc < CURRENT_DATE()"
    )


def order_type_clause(order_type: Optional[str]) -> str:
    """Restrict to Regular (is_drive=FALSE) or Drive (is_drive=TRUE) orders."""
    ot = norm_order_type(order_type)
    if ot == ORDER_TYPE_DRIVE:
        return "AND fp.is_drive = TRUE"
    return "AND fp.is_drive = FALSE"


def period_suffix(
    complete_weeks: Optional[int],
    date_from: Optional[str],
    date_to: Optional[str],
) -> Optional[str]:
    """Cache-suffix fragment for the period (the rolling-days case is already
    encoded by ``cache_by_lookback`` in the filename base, so it adds nothing)."""
    if date_from and date_to:
        return f"d{date_from}_{date_to}"
    if complete_weeks:
        return f"w{int(complete_weeks)}"
    return None


def order_type_suffix(order_type: Optional[str]) -> Optional[str]:
    """Cache-suffix fragment for the order type. ``regular`` (the default) adds
    NOTHING so it keeps reading the historical default-warmed files; ``drive``
    gets its own ``ot-drive`` slice."""
    return "ot-drive" if norm_order_type(order_type) == ORDER_TYPE_DRIVE else None


# --- TTLA calculation-logic modes ---------------------------------------------
# A global TTLA-tab filter that swaps HOW each order's TTLA is computed. The
# order SET is unchanged (still filtered by city / period / order type /
# delivery-counts / size / venue-type / ...); only the per-order TTLA value
# differs by mode.
#
#   default        -> f_purchases.time_to_last_accept_sec (the combined metric:
#                     last pickup-accept minus the order's FIRST task-shown;
#                     includes idle gaps on reassigns / splits). Current behavior.
#   first_courier  -> the 1st (original) task group's own TIME_TO_LAST_ACCEPT,
#                     i.e. the courier who was shown the task first. Isolates that
#                     courier's accept speed (no upstream idle gap from a later
#                     courier's task). The "1st" task group = the one whose
#                     is_duplicate is FALSE or NULL (the original; NULL is
#                     treated as non-duplicate, matching the rest of the codebase).
#   fixed          -> AVG(TIME_TO_LAST_ACCEPT) over ALL of the order's task groups
#                     (each courier's own per-task TTLA, idle gaps excluded). The
#                     order-list TTLA column shows this average; the city/country/
#                     venue/courier panels use the order-weighted mean of these
#                     per-order averages (denominator = order count).
#
# For deliveries_count = 1 all three coincide (one task group). Modes 2/3 derive
# the value from presentation.task_groups_enriched via a helper CTE
# (``tg_per_purchase``) pre-aggregated to one row per purchase, then LEFT JOINed
# into fp_base so the existing per-purchase QUALIFY dedup is unaffected. The CTE
# is scoped to the same f_purchases population (country [+ city] / window /
# order type / status / provider) via a semi-join so f_purchases' per-purchase
# dup rows don't fan out the task-group aggregation. The population is passed in
# as a pre-formatted ``population_clause`` (built by
# ``ttla_tab_population_clause`` for the TTLA tab or
# ``country_ttla_population_clause`` for the Country tab) so the two tabs — which
# filter f_purchases differently (the TTLA tab composes order_type + date_window;
# the Country tab hardcodes the pure on-demand filters + a rolling window) —
# each scope the CTE to EXACTLY their outer query's WHERE.
TTLA_MODE_DEFAULT = "default"
TTLA_MODE_FIRST_COURIER = "first_courier"
TTLA_MODE_FIXED = "fixed"
TTLA_MODES = {TTLA_MODE_DEFAULT, TTLA_MODE_FIRST_COURIER, TTLA_MODE_FIXED}


def norm_ttla_mode(mode: Optional[str]) -> str:
    """Normalize the TTLA-calculation-mode slug; anything unknown falls back to
    ``default`` (the historical behavior), so an old/missing value keeps reading
    the existing default-warmed cache files."""
    return mode if mode in TTLA_MODES else TTLA_MODE_DEFAULT


def ttla_mode_suffix(mode: Optional[str]) -> Optional[str]:
    """Cache-suffix fragment for the TTLA mode. ``default`` adds NOTHING so it
    keeps reading the historical default-warmed files; the other modes get their
    own slice (``tm-first`` / ``tm-fixed``) so a mode never collides with the
    default cache file or the other mode."""
    m = norm_ttla_mode(mode)
    if m == TTLA_MODE_FIRST_COURIER:
        return "tm-first"
    if m == TTLA_MODE_FIXED:
        return "tm-fixed"
    return None


def _tg_per_purchase_cte_body(
    country: str,
    city: Optional[str],
    population_clause: str,
) -> str:
    """The ``tg_per_purchase`` CTE body (without the leading ``tg_per_purchase AS
    (`` / trailing ``)``), pre-aggregated to one row per purchase so the LEFT JOIN
    into fp_base never fans out. Scoped to the same f_purchases population via a
    semi-join (``purchase_id IN (SELECT ...)``) so the per-purchase dup rows in
    f_purchases don't multiply the task-group aggregation. ``city=None`` scopes
    to the whole country (used by the country-context / country-master views);
    otherwise to that one operations area (cuts the work for the city panels).

    ``population_clause`` is the FULL WHERE fragment (each condition already
    ``AND``-prefixed) that defines the f_purchases population AFTER the country
    [+ city] filter — i.e. status / delivery_provider_type / order-type / drive /
    preorder / time-slot / date-window. Pre-formatted (no remaining
    ``str.format`` placeholders) so the two tabs that share this helper — the
    TTLA tab (status+provider+order_type+date_window) and the Country tab
    (status+provider+is_drive=FALSE+is_preorder=FALSE+is_time_slot_order=FALSE+
    rolling window) — each bake their own population in and the CTE scoping
    always matches the outer query's WHERE exactly."""
    city_clause = (
        f"AND fp.venue_operations_area = '{_sql_str(city)}'" if city else ""
    )
    return (
        "tg_per_purchase AS (\n"
        "  SELECT tg.purchase_id,\n"
        "         MAX(IFF(NOT COALESCE(tg.is_duplicate, FALSE), tg.\"TIME_TO_LAST_ACCEPT\", NULL)) AS first_ttla,\n"
        "         AVG(tg.\"TIME_TO_LAST_ACCEPT\") AS fixed_ttla\n"
        "  FROM presentation.task_groups_enriched AS tg\n"
        "  WHERE tg.\"TIME_TO_LAST_ACCEPT\" IS NOT NULL\n"
        "    AND tg.purchase_id IN (\n"
        "      SELECT fp.purchase_id FROM INTERMEDIATE.f_purchases AS fp\n"
        "      WHERE fp.venue_country = '{country}'\n"
        "        {city_clause}\n"
        "        {population_clause}\n"
        "    )\n"
        "  GROUP BY tg.purchase_id\n"
        ")"
    ).format(
        country=_sql_str(country),
        city_clause=city_clause,
        population_clause=population_clause,
    )


def ttla_tab_population_clause(
    date_window_clause: str,
    order_type_clause: str,
) -> str:
    """The TTLA tab's f_purchases population (after country [+ city]):
    status+provider+order_type+date_window, pre-formatted into one AND-chain for
    the ``tg_per_purchase`` semi-join scoping."""
    return (
        "AND fp.status IN ('delivered','refunded') "
        "AND fp.delivery_provider_type = 'relay' "
        f"{order_type_clause} {date_window_clause}"
    )


def country_ttla_population_clause(lookback_days: int) -> str:
    """The Country tab's f_purchases population (after country [+ city]) for the
    TTLA mode CTE scoping: the SAME pure on-demand filters ``country_ttla*.sql``
    hardcode (status+provider+is_drive=FALSE+is_preorder=FALSE+
    is_time_slot_order=FALSE) plus the rolling UTC confirmed-date window
    (``{lookback_days}`` baked in). The Country tab's TTLA panel is fixed to the
    on-demand population (no Regular/Drive toggle), so this is a single
    pre-formatted clause, not composed from the TTLA tab's order_type/date
    helpers."""
    n = int(lookback_days)
    return (
        "AND fp.status IN ('delivered','refunded') "
        "AND fp.delivery_provider_type = 'relay' "
        "AND fp.is_drive = FALSE "
        "AND fp.is_preorder = FALSE "
        "AND fp.is_time_slot_order = FALSE "
        "AND fp.time_confirmed_utc >= DATEADD('day', -" + str(n) + ", CURRENT_DATE()) "
        "AND fp.time_confirmed_utc < CURRENT_DATE()"
    )


def ttla_mode_fragments(
    mode: Optional[str],
    country: str,
    city: Optional[str],
    population_clause: str,
) -> dict:
    """Return the SQL placeholder values that swap the per-order TTLA expression
    for the selected mode. ``default`` resolves to empty CTE/join + the raw
    ``f_purchases.time_to_last_accept_sec`` (today's SQL), so existing cache files
    stay valid. The other modes inject the ``tg_per_purchase`` CTE + LEFT JOIN and
    derive ``ttla_sec`` from it.

    ``population_clause`` scopes the helper CTE's f_purchases semi-join to the
    SAME population the outer query filters on (built by
    ``ttla_tab_population_clause`` for the TTLA tab or
    ``country_ttla_population_clause`` for the Country tab), so the task-group
    aggregation never drifts from the outer WHERE.

    Keys (consumed by the ttla_*.sql / country_ttla*.sql files; extra keys a
    file doesn't use are harmlessly ignored by str.format):
      ttla_cte_inner  -- for files with an existing WITH whose first CTE does
                         NOT join tg_per_purchase (orders/venues/couriers/
                         country_ttla_total/country_ttla): `` (default) |
                         `, tg_per_purchase AS (...)` (appended AFTER the first
                         CTE, so a LATER CTE — fp_base / the main SELECT — can
                         join it; SQL forbids forward CTE references).
      ttla_cte_prepend-- for files whose FIRST CTE itself joins tg_per_purchase
                         (country_ttla_by_city's fp_city): `` (default) |
                         ` tg_per_purchase AS (...),` (prepended BEFORE the
                         first CTE with a trailing comma, so `WITH{pre} fp_city`
                         -> `WITH tg_per_purchase AS (...), fp_city`).
      ttla_cte_outer  -- for files with NO existing WITH (country-context):
                         `` (default) | `WITH tg_per_purchase AS (...) `
      ttla_join       -- `` (default) | `LEFT JOIN tg_per_purchase AS tg ON ...`
      ttla_expr       -- the per-order TTLA value expression (CAST ... AS DOUBLE)
      ttla_not_null   -- the non-null filter for that expression
    """
    m = norm_ttla_mode(mode)
    if m == TTLA_MODE_DEFAULT:
        return {
            "ttla_cte_inner": "",
            "ttla_cte_prepend": "",
            "ttla_cte_outer": "",
            "ttla_join": "",
            "ttla_expr": "CAST(fp.time_to_last_accept_sec AS DOUBLE PRECISION)",
            "ttla_not_null": "fp.time_to_last_accept_sec IS NOT NULL",
        }
    body = _tg_per_purchase_cte_body(country, city, population_clause)
    if m == TTLA_MODE_FIRST_COURIER:
        expr = "CAST(tg.first_ttla AS DOUBLE PRECISION)"
        not_null = "tg.first_ttla IS NOT NULL"
    else:  # fixed
        expr = "CAST(tg.fixed_ttla AS DOUBLE PRECISION)"
        not_null = "tg.fixed_ttla IS NOT NULL"
    return {
        "ttla_cte_inner": f", {body}",
        "ttla_cte_prepend": f" {body},",
        "ttla_cte_outer": f"WITH {body} ",
        "ttla_join": "LEFT JOIN tg_per_purchase AS tg ON tg.purchase_id = fp.purchase_id",
        "ttla_expr": expr,
        "ttla_not_null": not_null,
    }
