with open("e:/GMWF/gmwf/lib/services/donations_local_storage.dart", "r", encoding="utf-8") as f:
    for idx, line in enumerate(f):
        if "downloadAllDonations" in line:
            print(f"Line {idx+1}: {line.strip()}")
