import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/madrassa/views/student_management_view.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if "widget _buildheader" in line.lower() or "void _buildheader" in line.lower():
        print(f"Line {idx+1}: {line.strip()}")
        # print next 120 lines
        for j in range(1, 120):
            if idx + j < len(lines):
                print(f"  +{j}: {lines[idx+j].rstrip()}")
        print("-" * 50)
        break
