"""Convert MCP query output files to JSON arrays of dicts."""
import json
import re
import sys
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
        "1c6beeb4-806d-4031-868f-a5a18338ca89.txt": "base_late_orders_limassol.json",
        "9901b21d-f995-4a3d-b86a-958d343a71fd.txt": "delayed_orders_limassol.json",
        "75f5cdd2-6407-41b7-bf33-5be90d5e8140.txt": "base_late_orders_larnaca.json",
        "ea3a89cc-6b7e-4636-90a8-ae15c69b7d70.txt": "delayed_orders_larnaca.json",
    }
    
    for src, dst in files.items():
        convert_mcp_file(f"{base}/{src}", f"{data}/{dst}")
