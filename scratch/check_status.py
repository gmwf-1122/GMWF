import json, sys
data=json.load(open('e:/GMWF/gmwf/import_donations-1.json'))
non=[d for d in data if d.get('status')!='received']
print('Total records:', len(data))
print('Non-received count:', len(non))
if non:
    print('Sample non-received:', non[0])
