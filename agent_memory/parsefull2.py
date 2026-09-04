import re
raw = open('agent_memory/shots/real_chat_now.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    tm = re.search(r'text="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    d = (dm.group(1) if dm else '').strip()
    t = (tm.group(1) if tm else '').strip()
    if (d or t) and bm:
        rows.append((d or t, bm.group(1)))
out = '\n'.join('%s | %s' % (a,b) for a,b in rows)
open('agent_memory/logs/_chat_now.txt','w',encoding='utf-8').write(out)
print('ok')
