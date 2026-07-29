import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/scratch/parse_excel_to_json.py", "r", encoding="utf-8") as f:
    lines = f.readlines()

print("".join(lines[100:250]))
print("=" * 80)
print("".join(lines[250:]))
