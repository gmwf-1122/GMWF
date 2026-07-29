import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/madrassa/views/student_management_view.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines):
    if "widget _buildmobilestudentcard" in line.lower() or "_buildmobilestudentcard(" in line.lower():
        print(f"Start Line: {idx+1}")
        # search for end of method (where the next method starts or at matching braces)
        # Let's print the next 90 lines
        for j in range(95):
            if idx + j < len(lines):
                print(f"  +{j}: {lines[idx+j].rstrip()}")
        break
