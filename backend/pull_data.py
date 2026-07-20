"""
Pull data from Snowflake and save as JSON files for the dashboard.
Uses externalbrowser (Okta SSO) auth -- will open your browser to log in.

Usage:
    python pull_data.py                     # Pull all cities
    python pull_data.py Ridgeport Northgate      # Pull specific cities
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from datetime import date, datetime

DATA_DIR = Path(__file__).parent / "data"
SQL_DIR = Path(__file__).parent / "app" / "sql"

from dotenv import load_dotenv
load_dotenv(Path(__file__).parent.parent / ".env")

SUPPORTED_CITIES = ["Ridgeport", "Northgate", "Bayview", "Eastport", "Ridgeport"]
LOOKBACK = 90


def default_serializer(obj):
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    if hasattr(obj, '__float__'):
        return float(obj)
    return str(obj)


def pull_and_save():
    import snowflake.connector

    DATA_DIR.mkdir(exist_ok=True)

    cities = sys.argv[1:] if len(sys.argv) > 1 else SUPPORTED_CITIES

    account = os.environ.get("SNOWFLAKE_ACCOUNT", "")
    user = os.environ.get("SNOWFLAKE_USER", "")
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "")
    database = os.environ.get("SNOWFLAKE_DATABASE", "PRODUCTION")
    schema = os.environ.get("SNOWFLAKE_SCHEMA", "PUBLIC")
    role = os.environ.get("SNOWFLAKE_ROLE", "") or None
    authenticator = os.environ.get("SNOWFLAKE_AUTHENTICATOR", "externalbrowser")
    rotten_threshold = int(os.environ.get("ROTTEN_THRESHOLD_MIN", "20"))

    print(f"Connecting to Snowflake ({account}) as {user}...")
    print("Your browser will open for Okta login.")

    conn_params = {
        "account": account,
        "user": user,
        "warehouse": warehouse,
        "database": database,
        "schema": schema,
        "role": role,
        "authenticator": authenticator,
    }
    password = os.environ.get("SNOWFLAKE_PASSWORD", "")
    if password and authenticator != "externalbrowser":
        conn_params["password"] = password

    conn = snowflake.connector.connect(**conn_params)
    print("Connected!")

    cur = conn.cursor(snowflake.connector.DictCursor)

    for city in cities:
        safe = city.lower().replace(" ", "_")
        print(f"\n=== {city} ===")

        queries = {
            f"late_orders_summary_{safe}": ("late_orders_summary.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
            f"late_orders_trend_{safe}": ("late_orders_trend.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
            f"base_late_orders_{safe}": ("base_late_orders.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
            f"delayed_orders_{safe}": ("delayed_orders.sql", {
                "city": city, "lookback_days": LOOKBACK,
                "rotten_threshold_min": rotten_threshold,
            }),
            f"rotten_summary_{safe}": ("rotten_summary.sql", {
                "city": city, "lookback_days": LOOKBACK,
                "rotten_threshold_min": rotten_threshold,
            }),
            f"map_venues_{safe}": ("map_venues.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
            f"map_dropoffs_{safe}": ("map_dropoffs.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
            f"hourly_distribution_{safe}": ("hourly_distribution.sql", {
                "city": city, "lookback_days": LOOKBACK,
            }),
        }

        for name, (sql_file, params) in queries.items():
            print(f"  Pulling {name}...", end=" ", flush=True)
            sql = (SQL_DIR / sql_file).read_text().format(**params)
            try:
                cur.execute(sql)
                rows = [dict(r) for r in cur.fetchall()]
                out = DATA_DIR / f"{name}.json"
                out.write_text(json.dumps(rows, default=default_serializer, indent=2))
                print(f"{len(rows)} rows -> {out.name}")
            except Exception as e:
                print(f"FAILED: {e}")
                (DATA_DIR / f"{name}.json").write_text("[]")

    cur.close()
    conn.close()
    print("\nDone! Data saved to backend/data/")
    print("Start the dashboard with: uvicorn app.main:app --port 8000 --reload")


if __name__ == "__main__":
    pull_and_save()
