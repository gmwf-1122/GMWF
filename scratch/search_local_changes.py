import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/madrassa/views/daily_log_view.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if "_localchanges" in line.lower():
        print(f"Line {idx+1}: {line.strip()}")
        # print 5 lines before and after
        for j in range(-5, 6):
            if 0 <= idx + j < len(lines):
                print(f"  {j:+d}: {lines[idx+j].rstrip()}")
        print("-" * 50)
