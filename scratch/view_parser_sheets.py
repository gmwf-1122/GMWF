import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/scratch/parse_excel_to_json.py", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx in range(100, min(200, len(lines))):
    print(f"Line {idx+1}: {lines[idx].rstrip()}")
