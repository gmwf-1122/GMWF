with open("e:/GMWF/gmwf/lib/pages/donations/donations_dashboard.dart", "r", encoding="utf-8") as f:
    for idx, line in enumerate(f):
        if "_currentDonations" in line:
            print(f"Line {idx+1}: {line.strip()}")
