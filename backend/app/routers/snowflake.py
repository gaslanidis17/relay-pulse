from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.services.snowflake_client import connect_and_ping, connection_is_live
from app.services.activity_log import log_event

# Session (SSO) control for the shared Snowflake connection. Any signed-in user
# can ESTABLISH the session (which pops the one-time Okta browser login); after
# that, all the tabs' background auto-refresh can run without ever popping SSO
# again (they gate on ``connection_is_live()``). These endpoints are NOT in
# ``main.PUBLIC_PATHS``, so the AuthMiddleware still requires a dashboard login.
router = APIRouter(prefix="/api/snowflake", tags=["snowflake"])


@router.get("/status")
def snowflake_status():
    """Is the shared Snowflake session already established?

    Cheap, network-free boolean (``is_closed()`` on the cached connection). NEVER
    opens a connection, so polling this can't trigger an SSO popup. The frontend
    uses it to decide between the "Sign in to Snowflake" prompt and the normal
    freshness UI, and to detect when a sign-in elsewhere has come online.
    """
    return {"live": connection_is_live()}


@router.post("/connect")
def snowflake_connect():
    """Establish the shared Snowflake session on explicit user request.

    Runs a trivial ``SELECT 1`` through the shared connection, forcing the
    one-time Okta ``externalbrowser`` SSO popup if not already connected. This is
    the ONLY endpoint that may open a connection; every automatic refresh path
    gates on an already-live session instead. Returns ``{live: true}`` on success;
    surfaces a 502 (not 500) with the reason on connect/login failure so the UI
    can tell the user the sign-in didn't complete.
    """
    try:
        connect_and_ping()
    except Exception as exc:  # noqa: BLE001 — report, don't leak a stack trace
        log_event("snowflake", "connect_failed", detail={"error": str(exc)[:300]})
        raise HTTPException(
            status_code=502,
            detail="Could not connect to the warehouse. Complete the sign-in step and try again.",
        )
    log_event("snowflake", "connect_ok")
    return {"live": connection_is_live()}
