import re, sys
xml = open(sys.argv[1], encoding='utf-8').read()
texts = re.findall(r'text="([^"]*)"', xml)
descs = re.findall(r'content-desc="([^"]*)"', xml)
print('TEXTS:')
seen = set()
for t in texts:
    t = t.strip()
    if t and t not in seen:
        seen.add(t)
        print('  ', t)
print('DESCS:')
seen = set()
for t in descs:
    t = t.strip()
    if t and t not in seen:
        seen.add(t)
        print('  ', t)
