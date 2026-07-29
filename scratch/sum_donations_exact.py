import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

with open("e:/GMWF/gmwf/import_donations-1.json", "r", encoding="utf-8") as f:
    data = json.load(f)

# Categories
# Let's count by categoryId
categories = {}
for item in data:
    cat = item.get("categoryId", "unknown")
    status = item.get("status", "received")
    entry_type = item.get("entryType", "cash")
    amt = item.get("amount", 0)
    try:
        amt = float(amt)
    except:
        amt = 0.0
        
    categories.setdefault(cat, {"cash": 0.0, "online": 0.0, "goods": 0.0, "cancelled": 0.0})
    if status == "cancelled":
        categories[cat]["cancelled"] += amt
    elif entry_type == "goods":
        categories[cat]["goods"] += amt
    elif entry_type == "online":
        categories[cat]["online"] += amt
    else:
        categories[cat]["cash"] += amt

for cat, v in categories.items():
    print(f"Category: {cat}")
    print(f"  Cash: {v['cash']:,}")
    print(f"  Online: {v['online']:,}")
    print(f"  Goods: {v['goods']:,}")
    print(f"  Cancelled: {v['cancelled']:,}")
    print(f"  Sum Active: {v['cash'] + v['online'] + v['goods']:,}")
    print(f"  Sum Active (Cash/Online only): {v['cash'] + v['online']:,}")
