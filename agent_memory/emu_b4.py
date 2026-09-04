import re
raw = open('agent_memory/shots/emu_ui5.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if dm and bm:
        d = dm.group(1).strip()
        if d:
            rows.append((d, bm.group(1)))
out = '\n'.join('%s | %s' % (d,b) for d,b in rows)
open('agent_memory/logs/_eb4.txt','w',encoding='utf-8').write(out)
