import re, sys
raw = open('agent_memory/logs/emu_assist2.xml','rb').read()
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
open('agent_memory/logs/_parsed.txt','w',encoding='utf-8').write('\n'.join(out))
print('written')
