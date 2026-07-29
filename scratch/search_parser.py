import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/scratch/parse_excel_to_json.py", "r", encoding="utf-8") as f:
    content = f.read()

print(content[:1500])
print("=" * 50)
# search for 'goods' or 'cancel' or 'total' or '4149' or '19180'
for term in ['goods', 'cancel', 'total', '4149', '19180', 'GMWF']:
    if term in content:
        print(f"Term '{term}' found! Printing matching lines:")
        lines = content.split('\n')
        for idx, line in enumerate(lines):
            if term in line:
                print(f"  Line {idx+1}: {line.strip()}")
        print("-" * 50)
