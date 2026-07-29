import sys

# Reconfigure stdout to use utf-8 to avoid encoding errors on Windows console
sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/lib/pages/donations/donations_dashboard.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
    
for idx, line in enumerate(lines):
    if "_importDonations" in line:
        print(f"Line {idx+1}: {line.strip()}")
        # print next 40 lines
        for j in range(1, 40):
            if idx + j < len(lines):
                safe_line = lines[idx+j].rstrip()
                print(f"  +{j}: {safe_line}")
