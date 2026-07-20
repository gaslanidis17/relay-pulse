"""Convert query-export files to JSON arrays of dictionaries for a fictional demo city."""
import json
import re
from pathlib import Path

def convert_mcp_file(input_path: str, output_path: str):
    text = Path(input_path).read_text()

    cols_match = re.search(r'Columns:\s*(.+)', text)
    if not cols_match:
        print(f"No Columns line found in {input_path}")
        return

    columns = [c.strip() for c in cols_match.group(1).split(',')]

    results_match = re.search(r'Results:\s*\n(\[[\s\S]+)', text)
    if not results_match:
        print(f"No Results found in {input_path}")
        return

    rows = json.loads(results_match.group(1))

    dicts = []
    for row in rows:
        d = {}
        for i, col in enumerate(columns):
            d[col] = row[i] if i < len(row) else None
        dicts.append(d)

    Path(output_path).write_text(json.dumps(dicts, indent=2, default=str))
    print(f"Converted {len(dicts)} rows -> {output_path}")

if __name__ == "__main__":
    base = "/Users/ayan/.cursor/projects/Users-ayan-Documents-Cursor-Lateness-dashboard/agent-tools"
    data = "/Users/ayan/Documents/Cursor/Lateness dashboard/backend/data"

    files = {
        "f323524b-83a5-485e-b909-888928ae7871.txt": "base_late_orders_paphos.json",
        "e878f735-fe2f-4edb-ae81-f05b0f4c8901.txt": "delayed_orders_paphos.json",
    }

    for src, dst in files.items():
        convert_mcp_file(f"{base}/{src}", f"{data}/{dst}")
