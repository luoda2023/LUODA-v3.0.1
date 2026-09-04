import re
raw = open('agent_memory/shots/emu_id.xml','rb').read()
xml = raw.decode('utf-8', errors='replace')
rows = []
for m in re.finditer(r'<node[^>]*>', xml):
    tag = m.group(0)
    clsm = re.search(r'class="([^"]*)"', tag)
    bm = re.search(r'bounds="(\[[^"]*\])"', tag)
    if bm and clsm and 'EditText' in (clsm.group(1) or ''):
        rows.append((clsm.group(1), bm.group(1)))
out = '\n'.join('%s | %s' % r for r in rows)
open('agent_memory/logs/_emu_edit.txt','w',encoding='utf-8').write(out or 'NONE')
