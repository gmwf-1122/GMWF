import json, openpyxl

# Find GMWF records that are cancelled in JSON but have a real col2 amount in Excel
data = json.load(open('e:/GMWF/gmwf/import_donations-1.json'))

gmwf_cancelled = [d for d in data if d['categoryId']=='gmwf' and 'CANCELLED' in d.get('notes','')]
print(f"GMWF cancelled in JSON: {len(gmwf_cancelled)}")
for r in gmwf_cancelled[:20]:
    print(f"  {r['receiptNo']:>10} | {r['amount']:>8} | {r['donorName'][:30]} | {r['notes'][:60]}")

# Cross-check with Excel raw data
wb = openpyxl.load_workbook('e:/GMWF/gmwf/GRT DAILY Donation Record.xlsx', read_only=True)
print("\nRaw Excel data for GMWF cancelled receipts:")
cancelled_rcpts = {d['receiptNo'].rstrip('-ab') for d in gmwf_cancelled}
for sheet_name in ['GMWF', 'GMWF-25']:
    ws = wb[sheet_name]
    for r_idx, row in enumerate(ws.iter_rows(values_only=True)):
        if r_idx == 0: continue
        rc = str(row[1]).strip().rstrip('.0').strip() if row[1] else ''
        if rc in cancelled_rcpts:
            col2 = row[2] if len(row) > 2 else None
            col3 = str(row[3])[:20] if len(row) > 3 and row[3] else ''
            print(f"  [{sheet_name}] Row {r_idx}: rc={rc}, col2={col2}, col3={col3}")
wb.close()
