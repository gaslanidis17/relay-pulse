import json
import sys

def convert(input_path, output_path):
    with open(input_path, 'r') as f:
        text = f.read()

    columns_line = [l for l in text.split('\n') if l.startswith('Columns: ')][0]
    columns = [c.strip() for c in columns_line.replace('Columns: ', '').split(',')]

    results_start = text.index('Results:\n') + len('Results:\n')
    raw_json = text[results_start:]
    rows = json.loads(raw_json)

    records = []
    for row in rows:
        record = {}
        for i, col in enumerate(columns):
            record[col] = row[i]
        records.append(record)

    with open(output_path, 'w') as f:
        json.dump(records, f, indent=2, default=str)

    print(f"Converted {len(records)} rows -> {output_path}")

if __name__ == '__main__':
    convert(sys.argv[1], sys.argv[2])
