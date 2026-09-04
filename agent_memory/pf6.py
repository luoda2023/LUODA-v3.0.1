import re
raw = open('agent_memory/shots/real_bot.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    dm = re.search(r'content-desc="([^"]*)"', tag)
    clm = re.search(r'class="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    d = (dm.group(1) if dm else '').strip()
    if bm and (d or 'Button' in (clm.group(1) if clm else '')):
        rows.append((clm.group(1) if clm else '', d, bm.group(1)))
out = '\n'.join('%s | %s | %s' % r for r in rows)
open('agent_memory/logs/_bot.txt','w',encoding='utf-8').write(out)
