import re, sys, io
p = sys.argv[1]
raw = open(p, 'rb').read()
xml = raw.decode('utf-8', errors='replace')
texts = re.findall(r'text="([^"]*)"', xml)
descs = re.findall(r'content-desc="([^"]*)"', xml)
out = []
for t in texts:
    t = t.strip()
    if t: out.append('T: ' + t)
for t in descs:
    t = t.strip()
    if t: out.append('D: ' + t)
print('\n'.join(out))
