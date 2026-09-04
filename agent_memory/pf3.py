import re
raw = open('agent_memory/shots/real_chat2.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    tm = re.search(r'text="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    cls = re.search(r'class="([^"]*)"', tag)
    d = (dm.group(1) if dm else '').strip()
    t = (tm.group(1) if tm else '').strip()
    if (d or t) and bm:
        rows.append((cls.group(1) if cls else '', d or t, bm.group(1)))
out = '\n'.join('%s | %s | %s' % (a,b,c) for a,b,c in rows)
open('agent_memory/logs/_ch2.txt','w',encoding='utf-8').write(out)
print('ok')
