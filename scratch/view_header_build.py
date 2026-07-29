import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/madrassa/views/student_management_view.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx in range(920, min(975, len(lines))):
    print(f"Line {idx+1}: {lines[idx].rstrip()}")
