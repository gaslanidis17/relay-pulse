import json

INPUT_FILE = "/Users/ayan/.cursor/projects/Users-ayan-Documents-Cursor-Lateness-dashboard/agent-tools/eba5f57f-9e1a-4ae5-bb0b-3b7d192a07e3.txt"
OUTPUT_FILE = "/Users/ayan/Documents/Cursor/Lateness dashboard/backend/data/delayed_orders_almaty.json"

with open(INPUT_FILE, "r") as f:
    content = f.read()

for line in content.split("\n"):
    if line.startswith("Columns:"):
        columns = [c.strip() for c in line[len("Columns:"):].split(",")]
        break

results_start = content.index("Results:\n") + len("Results:\n")
results_json = content[results_start:]
rows = json.loads(results_json)

data = [dict(zip(columns, row)) for row in rows]

with open(OUTPUT_FILE, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"Row count: {len(data)}")
