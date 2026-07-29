import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/import_donations-1.json", "r", encoding="utf-8") as f:
    data = json.load(f)

print(f"Total donation records: {len(data)}")

# Let's count by category/branch
totals = {}
for item in data:
    b = item.get("branch", "unknown")
    t = item.get("type", "unknown") # cash, online, goods?
    is_cancelled = item.get("status") == "cancelled"
    
    # parse amount
    amt = item.get("amount", 0)
    try:
        amt = float(amt)
    except:
        amt = 0.0
        
    totals.setdefault(b, {"cash_online": 0.0, "goods": 0.0, "cancelled": 0.0})
    if is_cancelled:
        totals[b]["cancelled"] += amt
    elif t == "goods":
        totals[b]["goods"] += amt
    else:
        totals[b]["cash_online"] += amt

for b, v in totals.items():
    print(f"Branch: {b}")
    print(f"  Cash/Online: {v['cash_online']:,}")
    print(f"  Goods: {v['goods']:,}")
    print(f"  Cancelled: {v['cancelled']:,}")
    print(f"  Sum of Active: {v['cash_online'] + v['goods']:,}")
