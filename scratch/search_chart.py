import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/widgets/home_snapshot_widgets.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
    
for idx, line in enumerate(lines):
    if "HomePatientsByBranchBarChart" in line:
        print(f"Line {idx+1}: {line.strip()}")
