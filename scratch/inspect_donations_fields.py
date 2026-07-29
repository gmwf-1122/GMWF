import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/import_donations-1.json", "r", encoding="utf-8") as f:
    data = json.load(f)

for i in range(min(5, len(data))):
    print(json.dumps(data[i], indent=2, ensure_ascii=False))
