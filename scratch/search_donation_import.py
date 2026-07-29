import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/donations/donations_dashboard.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx in range(550, min(650, len(lines))):
    print(f"Line {idx+1}: {lines[idx].rstrip()}")
