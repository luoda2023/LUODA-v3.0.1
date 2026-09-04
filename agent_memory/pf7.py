import re
raw = open('agent_memory/shots/real_rfull.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
print('len', len(xml))
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    cl = re.search(r'class="([^"]*)"', tag)
    ck = re.search(r'clickable="([^"]*)"', tag)
    d = (dm.group(1) if dm else '').strip()
    if d and bm:
        rows.append((cl.group(1) if cl else '', d, bm.group(1), ck.group(1) if ck else ''))
out = '\n'.join('%s | %s | %s | %s' % r for r in rows)
open('agent_memory/logs/_rf.txt','w',encoding='utf-8').write(out)
print('nodes', len(rows))
