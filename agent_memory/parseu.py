import re, sys
p = sys.argv[1]
outp = sys.argv[2]
raw = open(p,'rb').read()
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
open(outp,'w',encoding='utf-8').write('\n'.join(out))
print('done', len(out))
